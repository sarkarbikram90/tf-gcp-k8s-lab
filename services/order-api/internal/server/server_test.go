package server_test

import (
	"bytes"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/sarkarbikram90/tf-gcp-k8s-lab/services/order-api/internal/server"
)

func newTestServer(t *testing.T, barnaclesURL, vllmURL string) *server.Server {
	t.Helper()
	logger := slog.New(slog.NewJSONHandler(io.Discard, nil))
	srv := server.New(server.Config{
		Port:              "8080",
		AppEnv:            "test",
		PodName:           "order-api-test-pod-01",
		PodNamespace:      "app-order-api",
		BarnaclesEndpoint: barnaclesURL,
		OpenAIAPIBase:     vllmURL,
		LLMModelName:      "meta-llama/Llama-3.1-8B-Instruct",
		LLMTimeout:        2 * time.Second,
	}, logger)
	t.Cleanup(func() {
		srv.Close()
	})
	return srv
}

func TestHealthAndReadinessDrain(t *testing.T) {
	srv := newTestServer(t, "", "")
	ts := httptest.NewServer(srv.Handler())
	defer ts.Close()

	// 1. Verify /healthz returns 200 OK
	resp, err := http.Get(ts.URL + "/healthz")
	if err != nil {
		t.Fatalf("GET /healthz failed: %v", err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("expected 200 OK from /healthz, got %d", resp.StatusCode)
	}

	// 2. Verify /readyz returns 200 OK when Ready
	resp, err = http.Get(ts.URL + "/readyz")
	if err != nil {
		t.Fatalf("GET /readyz failed: %v", err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("expected 200 OK from /readyz, got %d", resp.StatusCode)
	}

	// 3. Simulate SIGTERM pod drain -> /readyz must flip to 503 Service Unavailable
	srv.SetReady(false)
	resp, err = http.Get(ts.URL + "/readyz")
	if err != nil {
		t.Fatalf("GET /readyz after drain failed: %v", err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusServiceUnavailable {
		t.Fatalf("expected 503 ServiceUnavailable during drain, got %d", resp.StatusCode)
	}
}

func TestOrderLifecycleAndBarnaclesAndVLLMIntegration(t *testing.T) {
	var barnaclesEvents atomic.Int32
	barnaclesMock := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/v1/logs" && r.Method == http.MethodPost {
			barnaclesEvents.Add(1)
			w.WriteHeader(http.StatusAccepted)
			return
		}
		w.WriteHeader(http.StatusNotFound)
	}))
	defer barnaclesMock.Close()

	vllmMock := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/v1/chat/completions" && r.Method == http.MethodPost {
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`{"choices":[{"message":{"content":"APPROVED: normal enterprise GPU order."}}]}`))
			return
		}
		w.WriteHeader(http.StatusNotFound)
	}))
	defer vllmMock.Close()

	srv := newTestServer(t, barnaclesMock.URL+"/v1/logs", vllmMock.URL+"/v1")
	ts := httptest.NewServer(srv.Handler())
	defer ts.Close()

	// 1. Create an order with AI fraud risk assessment enabled
	reqBody := `{"customer_id":"cust-900","item_sku":"k8s-enterprise-support","quantity":1,"total_amount_usd":499.50,"assess_fraud_risk":true}`
	resp, err := http.Post(ts.URL+"/orders", "application/json", bytes.NewBufferString(reqBody))
	if err != nil {
		t.Fatalf("POST /orders failed: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusCreated {
		t.Fatalf("expected 201 Created, got %d", resp.StatusCode)
	}

	var created server.Order
	if err := json.NewDecoder(resp.Body).Decode(&created); err != nil {
		t.Fatalf("failed to decode created order: %v", err)
	}
	if created.ID == "" || created.Status != "CONFIRMED" {
		t.Fatalf("unexpected order response: %+v", created)
	}
	if !strings.Contains(created.AIRiskSummary, "APPROVED") {
		t.Fatalf("expected vLLM risk summary in response, got %q", created.AIRiskSummary)
	}

	// 2. Fetch the created order via GET /orders/{id}
	getResp, err := http.Get(ts.URL + "/orders/" + created.ID)
	if err != nil {
		t.Fatalf("GET /orders/%s failed: %v", created.ID, err)
	}
	defer getResp.Body.Close()
	if getResp.StatusCode != http.StatusOK {
		t.Fatalf("expected 200 OK on GET /orders/%s, got %d", created.ID, getResp.StatusCode)
	}

	// 3. Flush async log worker and verify Barnacles received the structured OTLP event
	srv.Close()
	if barnaclesEvents.Load() < 1 {
		t.Fatalf("expected at least 1 log event shipped to Barnacles, got %d", barnaclesEvents.Load())
	}

	// 4. Verify Prometheus /metrics output matches Golden Path SLO recording rules
	metricsResp, err := http.Get(ts.URL + "/metrics")
	if err != nil {
		t.Fatalf("GET /metrics failed: %v", err)
	}
	defer metricsResp.Body.Close()
	rawMetrics, _ := io.ReadAll(metricsResp.Body)
	metricsText := string(rawMetrics)

	expectedSeries := `http_requests_total{namespace="app-order-api",pod="order-api-test-pod-01",method="POST",route="/orders",status="201"} 1`
	if !strings.Contains(metricsText, expectedSeries) {
		t.Fatalf("expected Prometheus metric %q in:\n%s", expectedSeries, metricsText)
	}
}
