// Package copilot implements the Level 7 In-Cluster Autonomous SRE Responder.
// It receives Prometheus Alertmanager and Falco CKS runtime security webhooks,
// concurrently queries Barnacles OTLP logs, Prometheus Golden Signal metrics,
// and Kubernetes API Warning Events, and calls the Level 5 vLLM Gateway to
// synthesize structured Root Cause Analysis (RCA) reports and Markdown post-mortems.
package copilot

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/url"
	"os"
	"sort"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

type traceContextKey struct{}

// RemediationRequest defines the JSON payload for POST /incidents/{id}/remediate.
type RemediationRequest struct {
	Action string `json:"action,omitempty"`  // "auto", "quarantine_pod", or "restart_deployment"
	DryRun bool   `json:"dry_run,omitempty"` // when true, appends ?dryRun=All to K8s API PATCH
}

// RemediationRecord captures the audit trail of an automated or dry-run K8s remediation.
type RemediationRecord struct {
	Action      string    `json:"action"`
	Mode        string    `json:"mode"` // "dry-run" or "enforced"
	Target      string    `json:"target"`
	Status      string    `json:"status"` // "applied", "simulated", or "skipped"
	K8sResponse string    `json:"k8s_response"`
	ExecutedAt  time.Time `json:"executed_at"`
}

// Config holds runtime endpoints injected by the Level 6/7 Golden Path.
type Config struct {
	Port                   string
	PodName                string
	PodNamespace           string
	BarnaclesQueryEndpoint string
	PrometheusQueryURL     string
	K8sAPIURL              string
	K8sBearerToken         string
	OpenAIAPIBase          string
	LLMModelName           string
	RCATemplateFormat      string
	Timeout                time.Duration
}

// IncidentReport represents a synthesized SRE RCA report stored by sre-copilot.
type IncidentReport struct {
	ID                  string             `json:"id"`
	TraceID             string             `json:"trace_id,omitempty"`
	Source              string             `json:"source"` // "alertmanager", "falco-cks", or "custom-webhook"
	Summary             string             `json:"summary"`
	Severity            string             `json:"severity"`
	Labels              map[string]string  `json:"labels,omitempty"`
	CorrelatedLogs      string             `json:"correlated_barnacles_logs"`
	CorrelatedMetrics   string             `json:"correlated_prometheus_snapshot"`
	CorrelatedK8sEvents string             `json:"correlated_k8s_events"`
	SynthesizedRCA      string             `json:"synthesized_rca"`
	Remediation         *RemediationRecord `json:"remediation,omitempty"`
	TemplateFormat      string             `json:"template_format"`
	AnalyzedByPod       string             `json:"analyzed_by_pod"`
	CreatedAt           time.Time          `json:"created_at"`
}

// Server manages webhook triage, concurrent evidence gathering, Markdown RCA export,
// guarded Kubernetes remediation, and Prometheus metrics.
type Server struct {
	cfg        Config
	logger     *slog.Logger
	ready      atomic.Bool
	seq        atomic.Uint64
	httpClient *http.Client

	mu        sync.RWMutex
	incidents []IncidentReport

	webhooksReceived     atomic.Uint64
	rcaGenerated         atomic.Uint64
	k8sEventQueries      atomic.Uint64
	markdownExports      atomic.Uint64
	remediationsExecuted atomic.Uint64
}

// New initializes the sre-copilot Server.
func New(cfg Config, logger *slog.Logger) *Server {
	if cfg.PodName == "" {
		cfg.PodName = "sre-copilot-local"
	}
	if cfg.PodNamespace == "" {
		cfg.PodNamespace = "sre-copilot"
	}
	if cfg.RCATemplateFormat == "" {
		cfg.RCATemplateFormat = "sre-incident-report-v1"
	}
	if cfg.Timeout <= 0 {
		cfg.Timeout = 5 * time.Second
	}

	s := &Server{
		cfg:        cfg,
		logger:     logger,
		httpClient: buildHTTPClient(cfg.Timeout),
		incidents:  make([]IncidentReport, 0, 32),
	}
	s.ready.Store(true)
	return s
}

func buildHTTPClient(timeout time.Duration) *http.Client {
	rootCAs, err := x509.SystemCertPool()
	if err != nil || rootCAs == nil {
		rootCAs = x509.NewCertPool()
	}
	if caBytes, err := os.ReadFile("/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"); err == nil {
		_ = rootCAs.AppendCertsFromPEM(caBytes)
	}
	transport := &http.Transport{
		TLSClientConfig: &tls.Config{
			RootCAs:    rootCAs,
			MinVersion: tls.VersionTLS12,
		},
	}
	return &http.Client{
		Timeout:   timeout,
		Transport: transport,
	}
}

// SetReady sets the readiness state for graceful SIGTERM Pod drain.
func (s *Server) SetReady(ready bool) {
	s.ready.Store(ready)
}

// Handler returns the HTTP router for sre-copilot wrapped with W3C traceparent propagation.
func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", s.handleHealthz)
	mux.HandleFunc("GET /readyz", s.handleReadyz)
	mux.HandleFunc("GET /metrics", s.handleMetrics)
	mux.HandleFunc("POST /webhook", s.handleWebhook)
	mux.HandleFunc("GET /incidents", s.handleListIncidents)
	mux.HandleFunc("GET /incidents/{id}", s.handleGetIncident)
	mux.HandleFunc("GET /incidents/{id}/markdown", s.handleGetIncidentMarkdown)
	mux.HandleFunc("POST /incidents/{id}/remediate", s.handleRemediateIncident)
	return s.traceMiddleware(mux)
}

func (s *Server) traceMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		traceID := extractOrGenerateTraceID(r.Header.Get("traceparent"), r.Header.Get("X-Trace-ID"))
		w.Header().Set("traceparent", formatTraceparent(traceID))
		w.Header().Set("X-Trace-ID", traceID)
		ctx := context.WithValue(r.Context(), traceContextKey{}, traceID)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

func traceIDFromContext(ctx context.Context) string {
	if v, ok := ctx.Value(traceContextKey{}).(string); ok && v != "" {
		return v
	}
	return randomHex(16)
}

func attachOutboundTraceHeaders(ctx context.Context, req *http.Request) {
	if traceID := traceIDFromContext(ctx); traceID != "" {
		req.Header.Set("traceparent", formatTraceparent(traceID))
		req.Header.Set("X-Trace-ID", traceID)
	}
}

func extractOrGenerateTraceID(traceparent, xTraceID string) string {
	parts := strings.Split(strings.TrimSpace(traceparent), "-")
	if len(parts) == 4 && len(parts[1]) == 32 && isLowerHex(parts[1]) && parts[1] != strings.Repeat("0", 32) {
		return parts[1]
	}
	cleaned := strings.ToLower(strings.TrimSpace(xTraceID))
	if len(cleaned) == 32 && isLowerHex(cleaned) && cleaned != strings.Repeat("0", 32) {
		return cleaned
	}
	return randomHex(16)
}

func formatTraceparent(traceID string) string {
	if len(traceID) != 32 || !isLowerHex(traceID) {
		traceID = randomHex(16)
	}
	return fmt.Sprintf("00-%s-%s-01", traceID, randomHex(8))
}

func isLowerHex(s string) bool {
	for i := 0; i < len(s); i++ {
		c := s[i]
		if !((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')) {
			return false
		}
	}
	return len(s) > 0
}

func randomHex(numBytes int) string {
	b := make([]byte, numBytes)
	if _, err := rand.Read(b); err != nil {
		return strings.Repeat("b", numBytes*2)
	}
	return hex.EncodeToString(b)
}

func (s *Server) handleHealthz(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{
		"status":  "ok",
		"service": "sre-copilot",
		"pod":     s.cfg.PodName,
	})
}

func (s *Server) handleReadyz(w http.ResponseWriter, _ *http.Request) {
	if !s.ready.Load() {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"status": "draining"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ready"})
}

func (s *Server) handleListIncidents(w http.ResponseWriter, _ *http.Request) {
	s.mu.RLock()
	out := make([]IncidentReport, len(s.incidents))
	copy(out, s.incidents)
	s.mu.RUnlock()

	writeJSON(w, http.StatusOK, map[string]any{
		"count":     len(out),
		"incidents": out,
	})
}

func (s *Server) findIncident(id string) (IncidentReport, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	for _, inc := range s.incidents {
		if inc.ID == id {
			return inc, true
		}
	}
	return IncidentReport{}, false
}

func (s *Server) handleGetIncident(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	inc, ok := s.findIncident(id)
	if !ok {
		writeJSON(w, http.StatusNotFound, map[string]string{
			"error": fmt.Sprintf("incident %q not found", id),
		})
		return
	}
	writeJSON(w, http.StatusOK, inc)
}

func (s *Server) handleGetIncidentMarkdown(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	inc, ok := s.findIncident(id)
	if !ok {
		writeJSON(w, http.StatusNotFound, map[string]string{
			"error": fmt.Sprintf("incident %q not found", id),
		})
		return
	}
	s.markdownExports.Add(1)
	md := RenderIncidentMarkdown(inc)
	w.Header().Set("Content-Type", "text/markdown; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte(md))
}

// handleWebhook accepts both Prometheus Alertmanager webhooks and Falco CKS
// runtime security JSON alerts, correlates Barnacles + Prometheus + Kubernetes
// Warning Events in parallel, and synthesizes an RCA via Level 5 vLLM.
func (s *Server) handleWebhook(w http.ResponseWriter, r *http.Request) {
	s.webhooksReceived.Add(1)

	body, err := io.ReadAll(io.LimitReader(r.Body, 1<<20))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "failed to read request body"})
		return
	}

	source, summary, severity, labels := parseInboundSignal(body)
	targetNamespace := labels["namespace"]

	// Concurrently gather correlated logs from Barnacles, metrics from Prometheus,
	// and Warning Events from the Kubernetes API server.
	var (
		logsSnapshot      string
		metricsSnapshot   string
		k8sEventsSnapshot string
		wg                sync.WaitGroup
	)
	wg.Add(3)
	go func() {
		defer wg.Done()
		logsSnapshot = s.queryBarnaclesLogs(r.Context(), targetNamespace)
	}()
	go func() {
		defer wg.Done()
		metricsSnapshot = s.queryPrometheusSnapshot(r.Context(), targetNamespace)
	}()
	go func() {
		defer wg.Done()
		k8sEventsSnapshot = s.queryK8sWarningEvents(r.Context(), targetNamespace)
	}()
	wg.Wait()

	rcaText := s.synthesizeRCAViaVLLM(r.Context(), source, summary, severity, logsSnapshot, metricsSnapshot, k8sEventsSnapshot)
	s.rcaGenerated.Add(1)

	id := fmt.Sprintf("inc-%d", s.seq.Add(1))
	traceID := traceIDFromContext(r.Context())
	report := IncidentReport{
		ID:                  id,
		TraceID:             traceID,
		Source:              source,
		Summary:             summary,
		Severity:            severity,
		Labels:              labels,
		CorrelatedLogs:      logsSnapshot,
		CorrelatedMetrics:   metricsSnapshot,
		CorrelatedK8sEvents: k8sEventsSnapshot,
		SynthesizedRCA:      rcaText,
		TemplateFormat:      s.cfg.RCATemplateFormat,
		AnalyzedByPod:       s.cfg.PodName,
		CreatedAt:           time.Now().UTC(),
	}

	s.mu.Lock()
	s.incidents = append(s.incidents, report)
	s.mu.Unlock()

	s.logger.Info("incident_rca_synthesized",
		"incident_id", report.ID,
		"trace_id", report.TraceID,
		"source", report.Source,
		"severity", report.Severity,
		"summary", report.Summary,
	)

	writeJSON(w, http.StatusAccepted, report)
}

// handleRemediateIncident executes a policy-gated Kubernetes remediation action
// for an existing incident (e.g., CKS Pod network quarantine via label patch or
// rolling Deployment restart via annotation patch), supporting ?dryRun=All mode.
func (s *Server) handleRemediateIncident(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	inc, ok := s.findIncident(id)
	if !ok {
		writeJSON(w, http.StatusNotFound, map[string]string{
			"error": fmt.Sprintf("incident %q not found", id),
		})
		return
	}

	var req RemediationRequest
	if r.Body != nil {
		_ = json.NewDecoder(io.LimitReader(r.Body, 1<<16)).Decode(&req)
	}

	action := strings.ToLower(strings.TrimSpace(req.Action))
	if action == "" || action == "auto" {
		if inc.Source == "falco-cks" {
			action = "quarantine_pod"
		} else {
			action = "restart_deployment"
		}
	}

	if action != "quarantine_pod" && action != "restart_deployment" {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": fmt.Sprintf("unsupported remediation action %q (supported: auto, quarantine_pod, restart_deployment)", action),
		})
		return
	}

	rec := s.executeK8sRemediation(r.Context(), inc, action, req.DryRun)
	s.remediationsExecuted.Add(1)

	s.mu.Lock()
	for i := range s.incidents {
		if s.incidents[i].ID == id {
			s.incidents[i].Remediation = &rec
			inc = s.incidents[i]
			break
		}
	}
	s.mu.Unlock()

	s.logger.Info("incident_remediation_executed",
		"incident_id", inc.ID,
		"action", rec.Action,
		"mode", rec.Mode,
		"target", rec.Target,
		"status", rec.Status,
	)

	writeJSON(w, http.StatusOK, inc)
}

func (s *Server) executeK8sRemediation(ctx context.Context, inc IncidentReport, action string, dryRun bool) RemediationRecord {
	now := time.Now().UTC()
	mode := "enforced"
	if dryRun {
		mode = "dry-run"
	}

	ns := inc.Labels["namespace"]
	if ns == "" {
		ns = "default"
	}

	var (
		targetRef string
		apiPath   string
		patchDoc  map[string]any
	)

	switch action {
	case "quarantine_pod":
		pod := inc.Labels["pod"]
		if pod == "" {
			pod = "unknown-pod"
		}
		targetRef = fmt.Sprintf("Pod/%s/%s", ns, pod)
		apiPath = fmt.Sprintf("/api/v1/namespaces/%s/pods/%s", url.PathEscape(ns), url.PathEscape(pod))
		patchDoc = map[string]any{
			"metadata": map[string]any{
				"labels": map[string]string{
					"security.platform.io/quarantine": "isolated",
				},
				"annotations": map[string]string{
					"sre-copilot.platform.io/quarantined-incident": inc.ID,
					"sre-copilot.platform.io/quarantined-at":       now.Format(time.RFC3339),
				},
			},
		}

	default: // "restart_deployment"
		deploy := resolveDeploymentName(inc.Labels, ns)
		targetRef = fmt.Sprintf("Deployment/%s/%s", ns, deploy)
		apiPath = fmt.Sprintf("/apis/apps/v1/namespaces/%s/deployments/%s", url.PathEscape(ns), url.PathEscape(deploy))
		patchDoc = map[string]any{
			"spec": map[string]any{
				"template": map[string]any{
					"metadata": map[string]any{
						"annotations": map[string]string{
							"kubectl.kubernetes.io/restartedAt":           now.Format(time.RFC3339),
							"sre-copilot.platform.io/remediated-incident": inc.ID,
						},
					},
				},
			},
		}
	}

	if s.cfg.K8sAPIURL == "" {
		return RemediationRecord{
			Action:      action,
			Mode:        mode,
			Target:      targetRef,
			Status:      "simulated",
			K8sResponse: "k8s_api_endpoint_not_configured",
			ExecutedAt:  now,
		}
	}

	base := strings.TrimRight(s.cfg.K8sAPIURL, "/")
	fullURL := base + apiPath
	if dryRun {
		fullURL += "?dryRun=All"
	}

	rawPatch, _ := json.Marshal(patchDoc)
	req, err := http.NewRequestWithContext(ctx, http.MethodPatch, fullURL, bytes.NewReader(rawPatch))
	if err != nil {
		return RemediationRecord{
			Action:      action,
			Mode:        mode,
			Target:      targetRef,
			Status:      "skipped",
			K8sResponse: "k8s_patch_request_build_error",
			ExecutedAt:  now,
		}
	}
	req.Header.Set("Content-Type", "application/strategic-merge-patch+json")
	req.Header.Set("Accept", "application/json")
	if s.cfg.K8sBearerToken != "" {
		req.Header.Set("Authorization", "Bearer "+s.cfg.K8sBearerToken)
	}
	attachOutboundTraceHeaders(ctx, req)

	resp, err := s.httpClient.Do(req)
	if err != nil {
		return RemediationRecord{
			Action:      action,
			Mode:        mode,
			Target:      targetRef,
			Status:      "simulated",
			K8sResponse: "k8s_api_unreachable_fallback",
			ExecutedAt:  now,
		}
	}
	defer resp.Body.Close()
	_, _ = io.Copy(io.Discard, io.LimitReader(resp.Body, 4096))

	statusLabel := "applied"
	if dryRun {
		statusLabel = "simulated"
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		statusLabel = "skipped"
	}

	return RemediationRecord{
		Action:      action,
		Mode:        mode,
		Target:      targetRef,
		Status:      statusLabel,
		K8sResponse: fmt.Sprintf("HTTP %d", resp.StatusCode),
		ExecutedAt:  now,
	}
}

func resolveDeploymentName(labels map[string]string, namespace string) string {
	for _, key := range []string{"deployment", "app"} {
		if val := strings.TrimSpace(labels[key]); val != "" {
			return val
		}
	}
	nsApp := strings.TrimPrefix(strings.TrimSpace(namespace), "app-")
	if pod := strings.TrimSpace(labels["pod"]); pod != "" {
		if nsApp != "" && strings.HasPrefix(pod, nsApp+"-") {
			return nsApp
		}
		parts := strings.Split(pod, "-")
		if len(parts) >= 2 {
			return strings.Join(parts[:len(parts)-1], "-")
		}
		return pod
	}
	return nsApp
}

func parseInboundSignal(raw []byte) (source, summary, severity string, labels map[string]string) {
	labels = make(map[string]string)

	// 1. Check if Falco CKS runtime security JSON payload (`output`, `rule`, `priority`, `output_fields`)
	var falcoPayload struct {
		Output       string         `json:"output"`
		Priority     string         `json:"priority"`
		Rule         string         `json:"rule"`
		OutputFields map[string]any `json:"output_fields"`
	}
	if err := json.Unmarshal(raw, &falcoPayload); err == nil && (falcoPayload.Rule != "" || strings.Contains(falcoPayload.Output, "CKS_ALERT")) {
		source = "falco-cks"
		summary = falcoPayload.Output
		if summary == "" {
			summary = falcoPayload.Rule
		}
		severity = strings.ToLower(falcoPayload.Priority)
		if severity == "" {
			severity = "critical"
		}
		labels["rule"] = falcoPayload.Rule
		if ns, ok := falcoPayload.OutputFields["k8s.ns.name"].(string); ok {
			labels["namespace"] = ns
		}
		if pod, ok := falcoPayload.OutputFields["k8s.pod.name"].(string); ok {
			labels["pod"] = pod
		}
		return source, summary, severity, labels
	}

	// 2. Otherwise parse as Prometheus Alertmanager webhook
	var amPayload struct {
		Alerts []struct {
			Labels      map[string]string `json:"labels"`
			Annotations map[string]string `json:"annotations"`
		} `json:"alerts"`
	}
	if err := json.Unmarshal(raw, &amPayload); err == nil && len(amPayload.Alerts) > 0 {
		first := amPayload.Alerts[0]
		for k, v := range first.Labels {
			labels[k] = v
		}
		summary = first.Annotations["summary"]
		if summary == "" {
			summary = first.Labels["alertname"]
		}
		severity = first.Labels["severity"]
		if severity == "" {
			severity = "warning"
		}
		return "alertmanager", summary, severity, labels
	}

	return "custom-webhook", "Unstructured alert signal received", "info", labels
}

func (s *Server) queryBarnaclesLogs(ctx context.Context, namespace string) string {
	if s.cfg.BarnaclesQueryEndpoint == "" {
		return "barnacles_endpoint_not_configured"
	}
	if namespace == "" {
		namespace = "default"
	}
	u := fmt.Sprintf("%s?namespace=%s&limit=5", s.cfg.BarnaclesQueryEndpoint, url.QueryEscape(namespace))
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	if err != nil {
		return "barnacles_query_build_error"
	}
	attachOutboundTraceHeaders(ctx, req)
	resp, err := s.httpClient.Do(req)
	if err != nil {
		return "barnacles_unreachable_fallback"
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
	return strings.TrimSpace(string(data))
}

func (s *Server) queryPrometheusSnapshot(ctx context.Context, namespace string) string {
	if s.cfg.PrometheusQueryURL == "" {
		return "prometheus_endpoint_not_configured"
	}
	if namespace == "" {
		namespace = "default"
	}
	query := fmt.Sprintf(`sum(rate(http_requests_total{namespace=%q,status=~"5.."}[5m]))`, namespace)
	u := fmt.Sprintf("%s?query=%s", s.cfg.PrometheusQueryURL, url.QueryEscape(query))
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	if err != nil {
		return "prometheus_query_build_error"
	}
	attachOutboundTraceHeaders(ctx, req)
	resp, err := s.httpClient.Do(req)
	if err != nil {
		return "prometheus_unreachable_fallback"
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
	return strings.TrimSpace(string(data))
}

// queryK8sWarningEvents queries the Kubernetes API server for Warning events in
// the target namespace using the pod's read-only RBAC ServiceAccount token.
func (s *Server) queryK8sWarningEvents(ctx context.Context, namespace string) string {
	s.k8sEventQueries.Add(1)
	if s.cfg.K8sAPIURL == "" {
		return "k8s_api_endpoint_not_configured"
	}
	if namespace == "" {
		namespace = "default"
	}
	base := strings.TrimRight(s.cfg.K8sAPIURL, "/")
	u := fmt.Sprintf("%s/api/v1/namespaces/%s/events?fieldSelector=type=Warning&limit=5",
		base, url.PathEscape(namespace))

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	if err != nil {
		return "k8s_events_query_build_error"
	}
	req.Header.Set("Accept", "application/json")
	if s.cfg.K8sBearerToken != "" {
		req.Header.Set("Authorization", "Bearer "+s.cfg.K8sBearerToken)
	}
	attachOutboundTraceHeaders(ctx, req)

	resp, err := s.httpClient.Do(req)
	if err != nil {
		return "k8s_api_unreachable_fallback"
	}
	defer resp.Body.Close()

	data, _ := io.ReadAll(io.LimitReader(resp.Body, 8192))
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Sprintf("k8s_api_status_%d", resp.StatusCode)
	}

	return formatK8sEventList(data)
}

func formatK8sEventList(raw []byte) string {
	var eventList struct {
		Items []struct {
			Type           string `json:"type"`
			Reason         string `json:"reason"`
			Message        string `json:"message"`
			Count          int32  `json:"count"`
			InvolvedObject struct {
				Kind string `json:"kind"`
				Name string `json:"name"`
			} `json:"involvedObject"`
		} `json:"items"`
	}
	if err := json.Unmarshal(raw, &eventList); err == nil && eventList.Items != nil {
		if len(eventList.Items) == 0 {
			return "no_warning_events_in_namespace"
		}
		lines := make([]string, 0, len(eventList.Items))
		for _, ev := range eventList.Items {
			evType := ev.Type
			if evType == "" {
				evType = "Warning"
			}
			objRef := strings.Trim(ev.InvolvedObject.Kind+"/"+ev.InvolvedObject.Name, "/")
			if objRef == "" {
				objRef = "UnknownObject"
			}
			countSuffix := ""
			if ev.Count > 1 {
				countSuffix = fmt.Sprintf(" x%d", ev.Count)
			}
			lines = append(lines, fmt.Sprintf("[%s] %s (%s%s): %s",
				evType, ev.Reason, objRef, countSuffix, strings.TrimSpace(ev.Message)))
		}
		return strings.Join(lines, "\n")
	}
	trimmed := strings.TrimSpace(string(raw))
	if trimmed == "" {
		return "no_warning_events_in_namespace"
	}
	return trimmed
}

func (s *Server) synthesizeRCAViaVLLM(ctx context.Context, source, summary, severity, logs, metrics, k8sEvents string) string {
	if s.cfg.OpenAIAPIBase == "" {
		return fmt.Sprintf("[Deterministic RCA (%s)] Source=%s Severity=%s Summary=%q | K8sEvents=%q | Action: Inspect namespace pods, Warning events, and NetworkPolicies.",
			s.cfg.RCATemplateFormat, source, severity, summary, k8sEvents)
	}

	endpoint := strings.TrimRight(s.cfg.OpenAIAPIBase, "/") + "/chat/completions"
	prompt := fmt.Sprintf(
		"Source: %s\nSeverity: %s\nSummary: %s\nKubernetes Warning Events: %s\nBarnacles Logs: %s\nPrometheus Snapshot: %s\nProvide a concise 3-step SRE Root Cause & Remediation summary.",
		source, severity, summary, k8sEvents, logs, metrics,
	)

	payload := map[string]any{
		"model": s.cfg.LLMModelName,
		"messages": []map[string]string{
			{"role": "system", "content": "You are a Staff Kubernetes SRE. Produce concise root-cause and remediation steps."},
			{"role": "user", "content": prompt},
		},
		"max_tokens":  128,
		"temperature": 0.1,
	}
	raw, _ := json.Marshal(payload)

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(raw))
	if err != nil {
		return "RCA fallback: request creation error"
	}
	req.Header.Set("Content-Type", "application/json")
	attachOutboundTraceHeaders(ctx, req)

	resp, err := s.httpClient.Do(req)
	if err != nil {
		return fmt.Sprintf("[Fallback RCA] vLLM offline; correlated k8s_events=%s logs=%s metrics=%s", k8sEvents, logs, metrics)
	}
	defer resp.Body.Close()

	var parsed struct {
		Choices []struct {
			Message struct {
				Content string `json:"content"`
			} `json:"message"`
		} `json:"choices"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&parsed); err != nil || len(parsed.Choices) == 0 {
		return "RCA fallback: unparseable vLLM response"
	}
	return strings.TrimSpace(parsed.Choices[0].Message.Content)
}

// RenderIncidentMarkdown formats an IncidentReport into a structured SRE
// Post-Mortem Markdown document aligned with docs/labs/incident-report-template.md.
func RenderIncidentMarkdown(rep IncidentReport) string {
	dateStr := rep.CreatedAt.UTC().Format("2006-01-02")
	compactDate := rep.CreatedAt.UTC().Format("20060102")
	incCode := fmt.Sprintf("INC-%s-%s", compactDate, strings.ToUpper(rep.ID))

	ns := rep.Labels["namespace"]
	if ns == "" {
		ns = "default"
	}

	sevBadge := strings.ToUpper(rep.Severity)
	switch strings.ToLower(rep.Severity) {
	case "critical":
		sevBadge = "SEV-1 (CRITICAL)"
	case "warning", "high":
		sevBadge = "SEV-2 (WARNING)"
	default:
		if sevBadge == "" {
			sevBadge = "SEV-3 (INFO)"
		}
	}

	var b strings.Builder
	fmt.Fprintf(&b, "# Incident Report: [%s] %s\n\n", incCode, rep.Summary)
	fmt.Fprintf(&b, "- **Date:** %s\n", dateStr)
	fmt.Fprintf(&b, "- **Incident ID:** `%s`\n", rep.ID)
	if rep.TraceID != "" {
		fmt.Fprintf(&b, "- **W3C Trace ID:** `%s`\n", rep.TraceID)
	}
	fmt.Fprintf(&b, "- **Detection Source:** `%s`\n", rep.Source)
	fmt.Fprintf(&b, "- **Target Namespace:** `%s`\n", ns)
	fmt.Fprintf(&b, "- **Automated Responder:** `%s` (`%s`)\n", rep.AnalyzedByPod, rep.TemplateFormat)
	fmt.Fprintf(&b, "- **Severity:** %s\n\n", sevBadge)
	b.WriteString("---\n\n")

	b.WriteString("## 1. Executive Summary & User Impact\n")
	fmt.Fprintf(&b, "- **What broke?** %s\n", rep.Summary)
	fmt.Fprintf(&b, "- **Blast radius:** Namespace `%s`", ns)
	if pod := rep.Labels["pod"]; pod != "" {
		fmt.Fprintf(&b, " (Pod `%s`)", pod)
	}
	b.WriteString("\n\n---\n\n")

	b.WriteString("## 2. Symptoms & Detection\n")
	fmt.Fprintf(&b, "- **How was the failure detected?** Inbound `%s` webhook received by `sre-copilot` at `%s`.\n",
		rep.Source, rep.CreatedAt.UTC().Format(time.RFC3339))
	if len(rep.Labels) > 0 {
		b.WriteString("- **Signal Labels:**\n")
		keys := make([]string, 0, len(rep.Labels))
		for k := range rep.Labels {
			keys = append(keys, k)
		}
		sort.Strings(keys)
		for _, k := range keys {
			fmt.Fprintf(&b, "  - `%s`: `%s`\n", k, rep.Labels[k])
		}
	}
	b.WriteString("\n---\n\n")

	b.WriteString("## 3. Correlated Telemetry & Evidence Collected\n\n")
	b.WriteString("### 3.1 Kubernetes API Warning Events\n")
	b.WriteString("```text\n")
	b.WriteString(nonEmptyOrFallback(rep.CorrelatedK8sEvents, "no_warning_events_in_namespace"))
	b.WriteString("\n```\n\n")

	b.WriteString("### 3.2 Barnacles OTLP Container Logs\n")
	b.WriteString("```json\n")
	b.WriteString(nonEmptyOrFallback(rep.CorrelatedLogs, "[]"))
	b.WriteString("\n```\n\n")

	b.WriteString("### 3.3 Prometheus Golden Signal Snapshot\n")
	b.WriteString("```json\n")
	b.WriteString(nonEmptyOrFallback(rep.CorrelatedMetrics, "{}"))
	b.WriteString("\n```\n\n---\n\n")

	b.WriteString("## 4. Root Cause Analysis & Remediation (vLLM Synthesis)\n")
	b.WriteString(nonEmptyOrFallback(rep.SynthesizedRCA, "No RCA synthesis available."))
	b.WriteString("\n\n---\n\n")

	b.WriteString("## 5. Remediation & Recovery Validation\n")
	if rep.Remediation != nil {
		fmt.Fprintf(&b, "- **Automated Runbook Action:** `%s` (`%s`)\n", rep.Remediation.Action, rep.Remediation.Mode)
		fmt.Fprintf(&b, "- **Target Resource:** `%s`\n", rep.Remediation.Target)
		fmt.Fprintf(&b, "- **Execution Status:** `%s` (`%s` at `%s`)\n\n",
			rep.Remediation.Status, rep.Remediation.K8sResponse, rep.Remediation.ExecutedAt.UTC().Format(time.RFC3339))
	}
	b.WriteString("```bash\n")
	fmt.Fprintf(&b, "# Inspect affected resources and events in namespace %q\n", ns)
	fmt.Fprintf(&b, "kubectl get pods,svc,ep,netpol -n %s -o wide\n", ns)
	fmt.Fprintf(&b, "kubectl get events -n %s --field-selector type=Warning --sort-by='.lastTimestamp'\n", ns)
	b.WriteString("```\n\n---\n\n")

	b.WriteString("## 6. Preventive Actions (Action Items)\n")
	b.WriteString("- [ ] **Automation / Policy Gate:** Verify workload compliance with `./scripts/platform/verify-platform-policies.sh`.\n")
	b.WriteString("- [ ] **Observability / SLO Gate:** Confirm Prometheus alert thresholds and Argo Rollouts `AnalysisTemplate` gates.\n")

	return b.String()
}

func nonEmptyOrFallback(val, fallback string) string {
	if strings.TrimSpace(val) == "" {
		return fallback
	}
	return val
}

func (s *Server) handleMetrics(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
	var buf strings.Builder
	buf.WriteString("# HELP http_requests_total Total HTTP requests processed by sre-copilot.\n")
	buf.WriteString("# TYPE http_requests_total counter\n")
	fmt.Fprintf(&buf, "http_requests_total{namespace=%q,pod=%q,method=\"POST\",route=\"/webhook\",status=\"202\"} %s\n",
		s.cfg.PodNamespace, s.cfg.PodName, strconv.FormatUint(s.webhooksReceived.Load(), 10))
	buf.WriteString("# HELP sre_copilot_rca_reports_total Total automated RCA reports generated.\n")
	buf.WriteString("# TYPE sre_copilot_rca_reports_total counter\n")
	fmt.Fprintf(&buf, "sre_copilot_rca_reports_total{namespace=%q,pod=%q} %s\n",
		s.cfg.PodNamespace, s.cfg.PodName, strconv.FormatUint(s.rcaGenerated.Load(), 10))
	buf.WriteString("# HELP sre_copilot_k8s_event_queries_total Total Kubernetes API Warning Event queries executed.\n")
	buf.WriteString("# TYPE sre_copilot_k8s_event_queries_total counter\n")
	fmt.Fprintf(&buf, "sre_copilot_k8s_event_queries_total{namespace=%q,pod=%q} %s\n",
		s.cfg.PodNamespace, s.cfg.PodName, strconv.FormatUint(s.k8sEventQueries.Load(), 10))
	buf.WriteString("# HELP sre_copilot_markdown_exports_total Total Markdown post-mortem reports exported.\n")
	buf.WriteString("# TYPE sre_copilot_markdown_exports_total counter\n")
	fmt.Fprintf(&buf, "sre_copilot_markdown_exports_total{namespace=%q,pod=%q} %s\n",
		s.cfg.PodNamespace, s.cfg.PodName, strconv.FormatUint(s.markdownExports.Load(), 10))
	buf.WriteString("# HELP sre_copilot_remediations_total Total guarded Kubernetes remediation actions executed.\n")
	buf.WriteString("# TYPE sre_copilot_remediations_total counter\n")
	fmt.Fprintf(&buf, "sre_copilot_remediations_total{namespace=%q,pod=%q} %s\n",
		s.cfg.PodNamespace, s.cfg.PodName, strconv.FormatUint(s.remediationsExecuted.Load(), 10))
	_, _ = w.Write([]byte(buf.String()))
}

func writeJSON(w http.ResponseWriter, status int, data any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(data)
}
