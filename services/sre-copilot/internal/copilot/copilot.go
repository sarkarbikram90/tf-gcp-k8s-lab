// Package copilot implements the Level 7 In-Cluster Autonomous SRE Responder.
// It receives Prometheus Alertmanager and Falco CKS runtime security webhooks,
// concurrently queries Barnacles OTLP logs and Prometheus metrics, and calls
// the Level 5 vLLM Gateway to synthesize structured Root Cause Analysis (RCA) reports.
package copilot

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

// Config holds runtime endpoints injected by the Level 6/7 Golden Path.
type Config struct {
	Port                   string
	PodName                string
	PodNamespace           string
	BarnaclesQueryEndpoint string
	PrometheusQueryURL     string
	OpenAIAPIBase          string
	LLMModelName           string
	RCATemplateFormat      string
	Timeout                time.Duration
}

// IncidentReport represents a synthesized SRE RCA report stored by sre-copilot.
type IncidentReport struct {
	ID                 string            `json:"id"`
	Source             string            `json:"source"` // "alertmanager" or "falco-cks"
	Summary            string            `json:"summary"`
	Severity           string            `json:"severity"`
	Labels             map[string]string `json:"labels,omitempty"`
	CorrelatedLogs     string            `json:"correlated_barnacles_logs"`
	CorrelatedMetrics  string            `json:"correlated_prometheus_snapshot"`
	SynthesizedRCA     string            `json:"synthesized_rca"`
	TemplateFormat     string            `json:"template_format"`
	AnalyzedByPod      string            `json:"analyzed_by_pod"`
	CreatedAt          time.Time         `json:"created_at"`
}

// Server manages webhook triage, concurrent evidence gathering, and Prometheus metrics.
type Server struct {
	cfg        Config
	logger     *slog.Logger
	ready      atomic.Bool
	seq        atomic.Uint64
	httpClient *http.Client

	mu        sync.RWMutex
	incidents []IncidentReport

	webhooksReceived atomic.Uint64
	rcaGenerated     atomic.Uint64
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
		httpClient: &http.Client{Timeout: cfg.Timeout},
		incidents:  make([]IncidentReport, 0, 32),
	}
	s.ready.Store(true)
	return s
}

// SetReady sets the readiness state for graceful SIGTERM Pod drain.
func (s *Server) SetReady(ready bool) {
	s.ready.Store(ready)
}

// Handler returns the HTTP router for sre-copilot.
func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", s.handleHealthz)
	mux.HandleFunc("GET /readyz", s.handleReadyz)
	mux.HandleFunc("GET /metrics", s.handleMetrics)
	mux.HandleFunc("POST /webhook", s.handleWebhook)
	mux.HandleFunc("GET /incidents", s.handleListIncidents)
	return mux
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

// handleWebhook accepts both Prometheus Alertmanager webhooks and Falco CKS
// runtime security JSON alerts, correlates Barnacles + Prometheus telemetry in
// parallel, and synthesizes an RCA via Level 5 vLLM.
func (s *Server) handleWebhook(w http.ResponseWriter, r *http.Request) {
	s.webhooksReceived.Add(1)

	body, err := io.ReadAll(io.LimitReader(r.Body, 1<<20))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "failed to read request body"})
		return
	}

	source, summary, severity, labels := parseInboundSignal(body)

	// Concurrently gather correlated logs from Barnacles and metrics from Prometheus
	var (
		logsSnapshot    string
		metricsSnapshot string
		wg              sync.WaitGroup
	)
	wg.Add(2)
	go func() {
		defer wg.Done()
		logsSnapshot = s.queryBarnaclesLogs(r.Context(), labels["namespace"])
	}()
	go func() {
		defer wg.Done()
		metricsSnapshot = s.queryPrometheusSnapshot(r.Context(), labels["namespace"])
	}()
	wg.Wait()

	rcaText := s.synthesizeRCAViaVLLM(r.Context(), source, summary, severity, logsSnapshot, metricsSnapshot)
	s.rcaGenerated.Add(1)

	id := fmt.Sprintf("inc-%d", s.seq.Add(1))
	report := IncidentReport{
		ID:                id,
		Source:            source,
		Summary:           summary,
		Severity:          severity,
		Labels:            labels,
		CorrelatedLogs:    logsSnapshot,
		CorrelatedMetrics: metricsSnapshot,
		SynthesizedRCA:    rcaText,
		TemplateFormat:    s.cfg.RCATemplateFormat,
		AnalyzedByPod:     s.cfg.PodName,
		CreatedAt:         time.Now().UTC(),
	}

	s.mu.Lock()
	s.incidents = append(s.incidents, report)
	s.mu.Unlock()

	s.logger.Info("incident_rca_synthesized",
		"incident_id", report.ID,
		"source", report.Source,
		"severity", report.Severity,
		"summary", report.Summary,
	)

	writeJSON(w, http.StatusAccepted, report)
}

func parseInboundSignal(raw []byte) (source, summary, severity string, labels map[string]string) {
	labels = make(map[string]string)

	// 1. Check if Falco CKS runtime security JSON payload (`output`, `rule`, `priority`, `output_fields`)
	var falcoPayload struct {
		Output       string            `json:"output"`
		Priority     string            `json:"priority"`
		Rule         string            `json:"rule"`
		OutputFields map[string]any    `json:"output_fields"`
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
	resp, err := s.httpClient.Do(req)
	if err != nil {
		return "prometheus_unreachable_fallback"
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
	return strings.TrimSpace(string(data))
}

func (s *Server) synthesizeRCAViaVLLM(ctx context.Context, source, summary, severity, logs, metrics string) string {
	if s.cfg.OpenAIAPIBase == "" {
		return fmt.Sprintf("[Deterministic RCA (%s)] Source=%s Severity=%s Summary=%q | Action: Inspect namespace pods and NetworkPolicies.",
			s.cfg.RCATemplateFormat, source, severity, summary)
	}

	endpoint := strings.TrimRight(s.cfg.OpenAIAPIBase, "/") + "/chat/completions"
	prompt := fmt.Sprintf(
		"Source: %s\nSeverity: %s\nSummary: %s\nBarnacles Logs: %s\nPrometheus Snapshot: %s\nProvide a concise 3-step SRE Root Cause & Remediation summary.",
		source, severity, summary, logs, metrics,
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

	resp, err := s.httpClient.Do(req)
	if err != nil {
		return fmt.Sprintf("[Fallback RCA] vLLM offline; correlated logs=%s metrics=%s", logs, metrics)
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
	_, _ = w.Write([]byte(buf.String()))
}

func writeJSON(w http.ResponseWriter, status int, data any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(data)
}
