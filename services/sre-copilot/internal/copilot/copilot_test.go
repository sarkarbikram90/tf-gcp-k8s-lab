package copilot_test

import (
	"bytes"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/sarkarbikram90/tf-gcp-k8s-lab/services/sre-copilot/internal/copilot"
)

func TestWebhookCorrelatesFalcoAndAlertmanagerWithBarnaclesAndVLLM(t *testing.T) {
	barnaclesMock := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`[{"level":"ERROR","msg":"connection refused to upstream db"}]`))
	}))
	defer barnaclesMock.Close()

	promMock := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"status":"success","data":{"result":[{"value":[1700000000,"0.12"]}]}}`))
	}))
	defer promMock.Close()

	vllmMock := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":"Root Cause: /etc/shadow read detected in container. Action: Isolate pod via NetworkPolicy."}}]}`))
	}))
	defer vllmMock.Close()

	logger := slog.New(slog.NewJSONHandler(io.Discard, nil))
	srv := copilot.New(copilot.Config{
		Port:                   "8080",
		PodName:                "sre-copilot-test-01",
		PodNamespace:           "sre-copilot",
		BarnaclesQueryEndpoint: barnaclesMock.URL + "/api/v1/query",
		PrometheusQueryURL:     promMock.URL + "/api/v1/query",
		OpenAIAPIBase:          vllmMock.URL + "/v1",
		LLMModelName:           "meta-llama/Llama-3.1-8B-Instruct",
		RCATemplateFormat:      "sre-incident-report-v1",
		Timeout:                2 * time.Second,
	}, logger)

	ts := httptest.NewServer(srv.Handler())
	defer ts.Close()

	// 1. Send a Falco CKS runtime security alert to POST /webhook
	falcoAlert := `{
		"output": "CKS_ALERT [SensitiveFileRead] Sensitive credential or PKI file read (file=/etc/shadow)",
		"priority": "CRITICAL",
		"rule": "CKS Sensitive Credential or PKI File Read in Container",
		"output_fields": {"k8s.ns.name": "app-order-api"}
	}`
	resp, err := http.Post(ts.URL+"/webhook", "application/json", bytes.NewBufferString(falcoAlert))
	if err != nil {
		t.Fatalf("POST /webhook failed: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusAccepted {
		t.Fatalf("expected 202 Accepted, got %d", resp.StatusCode)
	}

	var report copilot.IncidentReport
	if err := json.NewDecoder(resp.Body).Decode(&report); err != nil {
		t.Fatalf("failed to decode IncidentReport: %v", err)
	}
	if report.Source != "falco-cks" || !strings.Contains(report.SynthesizedRCA, "Isolate pod") {
		t.Fatalf("unexpected RCA report: %+v", report)
	}

	// 2. Verify GET /incidents returns the synthesized report
	incResp, err := http.Get(ts.URL + "/incidents")
	if err != nil {
		t.Fatalf("GET /incidents failed: %v", err)
	}
	defer incResp.Body.Close()
	if incResp.StatusCode != http.StatusOK {
		t.Fatalf("expected 200 OK from GET /incidents, got %d", incResp.StatusCode)
	}
}
