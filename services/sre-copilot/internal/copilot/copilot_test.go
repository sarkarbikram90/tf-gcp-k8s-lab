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

func TestWebhookCorrelatesFalcoAndAlertmanagerWithK8sEventsBarnaclesAndVLLM(t *testing.T) {
	barnaclesMock := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`[{"level":"ERROR","msg":"connection refused to upstream db"}]`))
	}))
	defer barnaclesMock.Close()

	promMock := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"status":"success","data":{"result":[{"value":[1700000000,"0.12"]}]}}`))
	}))
	defer promMock.Close()

	k8sEventsMock := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if gotAuth := r.Header.Get("Authorization"); gotAuth != "Bearer test-sa-jwt-token" {
			t.Errorf("expected Bearer token header, got %q", gotAuth)
		}
		if r.Method == http.MethodPatch {
			if ct := r.Header.Get("Content-Type"); ct != "application/strategic-merge-patch+json" {
				t.Errorf("expected strategic-merge-patch Content-Type, got %q", ct)
			}
			patchBody, _ := io.ReadAll(r.Body)
			if strings.Contains(r.URL.Path, "/api/v1/namespaces/app-order-api/pods/order-api-7f8b9") {
				if !strings.Contains(string(patchBody), `"security.platform.io/quarantine":"isolated"`) {
					t.Errorf("expected quarantine label in pod patch, got %s", string(patchBody))
				}
				w.WriteHeader(http.StatusOK)
				_, _ = w.Write([]byte(`{"kind":"Pod","metadata":{"name":"order-api-7f8b9"}}`))
				return
			}
			if strings.Contains(r.URL.Path, "/apis/apps/v1/namespaces/app-order-api/deployments/order-api") {
				if r.URL.Query().Get("dryRun") != "All" {
					t.Errorf("expected dryRun=All query param on dry_run deployment restart, got %q", r.URL.RawQuery)
				}
				if !strings.Contains(string(patchBody), `"kubectl.kubernetes.io/restartedAt"`) {
					t.Errorf("expected restartedAt annotation in deployment patch, got %s", string(patchBody))
				}
				w.WriteHeader(http.StatusOK)
				_, _ = w.Write([]byte(`{"kind":"Deployment","metadata":{"name":"order-api"}}`))
				return
			}
			t.Errorf("unexpected K8s PATCH path: %s", r.URL.Path)
		}
		if !strings.Contains(r.URL.Path, "/api/v1/namespaces/app-order-api/events") {
			t.Errorf("unexpected K8s events path: %s", r.URL.Path)
		}
		if r.URL.Query().Get("fieldSelector") != "type=Warning" {
			t.Errorf("expected fieldSelector=type=Warning, got %q", r.URL.Query().Get("fieldSelector"))
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{
			"kind": "EventList",
			"apiVersion": "v1",
			"items": [
				{
					"type": "Warning",
					"reason": "BackOff",
					"message": "Back-off restarting failed container app in pod order-api-7f8b9",
					"count": 4,
					"involvedObject": {
						"kind": "Pod",
						"name": "order-api-7f8b9"
					}
				}
			]
		}`))
	}))
	defer k8sEventsMock.Close()

	vllmMock := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		if !strings.Contains(string(body), "Back-off restarting failed container") {
			t.Errorf("expected vLLM prompt to include correlated K8s Warning events, got: %s", string(body))
		}
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
		K8sAPIURL:              k8sEventsMock.URL,
		K8sBearerToken:         "test-sa-jwt-token",
		OpenAIAPIBase:          vllmMock.URL + "/v1",
		LLMModelName:           "meta-llama/Llama-3.1-8B-Instruct",
		RCATemplateFormat:      "sre-incident-report-v1",
		Timeout:                2 * time.Second,
	}, logger)

	ts := httptest.NewServer(srv.Handler())
	defer ts.Close()

	// 1. Send a Falco CKS runtime security alert to POST /webhook with explicit W3C traceparent
	const expectedTraceID = "4bf92f3577b34da6a3ce929d0e0e4736"
	falcoAlert := `{
		"output": "CKS_ALERT [SensitiveFileRead] Sensitive credential or PKI file read (file=/etc/shadow)",
		"priority": "CRITICAL",
		"rule": "CKS Sensitive Credential or PKI File Read in Container",
		"output_fields": {
			"k8s.ns.name": "app-order-api",
			"k8s.pod.name": "order-api-7f8b9"
		}
	}`
	webhookReq, err := http.NewRequest(http.MethodPost, ts.URL+"/webhook", bytes.NewBufferString(falcoAlert))
	if err != nil {
		t.Fatalf("failed to build webhook request: %v", err)
	}
	webhookReq.Header.Set("Content-Type", "application/json")
	webhookReq.Header.Set("traceparent", "00-"+expectedTraceID+"-00f067aa0ba902b7-01")

	resp, err := http.DefaultClient.Do(webhookReq)
	if err != nil {
		t.Fatalf("POST /webhook failed: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusAccepted {
		t.Fatalf("expected 202 Accepted, got %d", resp.StatusCode)
	}
	if gotHeader := resp.Header.Get("X-Trace-ID"); gotHeader != expectedTraceID {
		t.Fatalf("expected X-Trace-ID header %q, got %q", expectedTraceID, gotHeader)
	}

	var report copilot.IncidentReport
	if err := json.NewDecoder(resp.Body).Decode(&report); err != nil {
		t.Fatalf("failed to decode IncidentReport: %v", err)
	}
	if report.TraceID != expectedTraceID {
		t.Fatalf("expected report.TraceID %q, got %q", expectedTraceID, report.TraceID)
	}
	if report.Source != "falco-cks" || !strings.Contains(report.SynthesizedRCA, "Isolate pod") {
		t.Fatalf("unexpected RCA report: %+v", report)
	}
	if !strings.Contains(report.CorrelatedK8sEvents, "[Warning] BackOff (Pod/order-api-7f8b9 x4)") {
		t.Fatalf("expected formatted K8s Warning event in report, got: %q", report.CorrelatedK8sEvents)
	}

	// 2. Execute closed-loop CKS pod quarantine remediation via POST /incidents/{id}/remediate
	remResp, err := http.Post(ts.URL+"/incidents/"+report.ID+"/remediate", "application/json",
		bytes.NewBufferString(`{"action":"auto","dry_run":false}`))
	if err != nil {
		t.Fatalf("POST /incidents/%s/remediate failed: %v", report.ID, err)
	}
	defer remResp.Body.Close()
	if remResp.StatusCode != http.StatusOK {
		t.Fatalf("expected 200 OK from POST /incidents/%s/remediate, got %d", report.ID, remResp.StatusCode)
	}
	var remediatedReport copilot.IncidentReport
	if err := json.NewDecoder(remResp.Body).Decode(&remediatedReport); err != nil {
		t.Fatalf("failed to decode remediated IncidentReport: %v", err)
	}
	if remediatedReport.Remediation == nil ||
		remediatedReport.Remediation.Action != "quarantine_pod" ||
		remediatedReport.Remediation.Status != "applied" {
		t.Fatalf("expected quarantine_pod remediation applied, got: %+v", remediatedReport.Remediation)
	}

	// 2b. Verify dry_run=true restart_deployment remediation via POST /incidents/{id}/remediate
	dryRemResp, err := http.Post(ts.URL+"/incidents/"+report.ID+"/remediate", "application/json",
		bytes.NewBufferString(`{"action":"restart_deployment","dry_run":true}`))
	if err != nil {
		t.Fatalf("POST /incidents/%s/remediate (dry_run) failed: %v", report.ID, err)
	}
	defer dryRemResp.Body.Close()
	if dryRemResp.StatusCode != http.StatusOK {
		t.Fatalf("expected 200 OK from dry_run remediate, got %d", dryRemResp.StatusCode)
	}

	// 3. Verify GET /incidents/{id} returns the single report
	singleResp, err := http.Get(ts.URL + "/incidents/" + report.ID)
	if err != nil {
		t.Fatalf("GET /incidents/%s failed: %v", report.ID, err)
	}
	defer singleResp.Body.Close()
	if singleResp.StatusCode != http.StatusOK {
		t.Fatalf("expected 200 OK from GET /incidents/%s, got %d", report.ID, singleResp.StatusCode)
	}

	// 4. Verify GET /incidents/{id}/markdown exports the structured SRE Post-Mortem Markdown
	mdResp, err := http.Get(ts.URL + "/incidents/" + report.ID + "/markdown")
	if err != nil {
		t.Fatalf("GET /incidents/%s/markdown failed: %v", report.ID, err)
	}
	defer mdResp.Body.Close()
	if mdResp.StatusCode != http.StatusOK {
		t.Fatalf("expected 200 OK from GET /incidents/%s/markdown, got %d", report.ID, mdResp.StatusCode)
	}
	if ct := mdResp.Header.Get("Content-Type"); !strings.HasPrefix(ct, "text/markdown") {
		t.Fatalf("expected Content-Type text/markdown, got %q", ct)
	}
	mdBytes, _ := io.ReadAll(mdResp.Body)
	mdText := string(mdBytes)
	for _, expectedSection := range []string{
		"# Incident Report: [INC-",
		"- **W3C Trace ID:** `" + expectedTraceID + "`",
		"## 1. Executive Summary & User Impact",
		"### 3.1 Kubernetes API Warning Events",
		"[Warning] BackOff (Pod/order-api-7f8b9 x4)",
		"### 3.2 Barnacles OTLP Container Logs",
		"### 3.3 Prometheus Golden Signal Snapshot",
		"## 4. Root Cause Analysis & Remediation (vLLM Synthesis)",
		"Isolate pod via NetworkPolicy",
		"- **Automated Runbook Action:** `restart_deployment` (`dry-run`)",
	} {
		if !strings.Contains(mdText, expectedSection) {
			t.Fatalf("expected markdown post-mortem to contain %q, got:\n%s", expectedSection, mdText)
		}
	}

	// 5. Verify 404 Not Found for unknown incident ID
	notFoundResp, err := http.Get(ts.URL + "/incidents/inc-9999/markdown")
	if err != nil {
		t.Fatalf("GET /incidents/inc-9999/markdown failed: %v", err)
	}
	defer notFoundResp.Body.Close()
	if notFoundResp.StatusCode != http.StatusNotFound {
		t.Fatalf("expected 404 Not Found, got %d", notFoundResp.StatusCode)
	}

	// 6. Verify Prometheus /metrics includes K8s event query, Markdown export, and Remediation counters
	metricsResp, err := http.Get(ts.URL + "/metrics")
	if err != nil {
		t.Fatalf("GET /metrics failed: %v", err)
	}
	defer metricsResp.Body.Close()
	metricsBody, _ := io.ReadAll(metricsResp.Body)
	metricsText := string(metricsBody)
	if !strings.Contains(metricsText, `sre_copilot_k8s_event_queries_total{namespace="sre-copilot",pod="sre-copilot-test-01"} 1`) {
		t.Fatalf("expected sre_copilot_k8s_event_queries_total=1 in /metrics, got:\n%s", metricsText)
	}
	if !strings.Contains(metricsText, `sre_copilot_markdown_exports_total{namespace="sre-copilot",pod="sre-copilot-test-01"} 1`) {
		t.Fatalf("expected sre_copilot_markdown_exports_total=1 in /metrics, got:\n%s", metricsText)
	}
	if !strings.Contains(metricsText, `sre_copilot_remediations_total{namespace="sre-copilot",pod="sre-copilot-test-01"} 2`) {
		t.Fatalf("expected sre_copilot_remediations_total=2 in /metrics, got:\n%s", metricsText)
	}
}
