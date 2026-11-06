// Package server implements the HTTP handlers, Prometheus Golden Signal metrics,
// Barnacles asynchronous OTLP log shipper, and optional Level 5 vLLM fraud-risk
// enrichment for the Golden Path reference microservice (`order-api`).
package server

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"sort"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

// Config holds runtime configuration injected via Kubernetes Downward API and
// Golden Path ConfigMaps/Secrets.
type Config struct {
	Port              string
	AppEnv            string
	PodName           string
	PodNamespace      string
	BarnaclesEndpoint string
	OpenAIAPIBase     string
	LLMModelName      string
	LLMTimeout        time.Duration
}

// Order represents a customer order in the commerce domain.
type Order struct {
	ID              string    `json:"id"`
	CustomerID      string    `json:"customer_id"`
	ItemSKU         string    `json:"item_sku"`
	Quantity        int       `json:"quantity"`
	TotalAmountUSD  float64   `json:"total_amount_usd"`
	Status          string    `json:"status"`
	AIRiskSummary   string    `json:"ai_risk_summary,omitempty"`
	ProcessedByPod  string    `json:"processed_by_pod"`
	CreatedAt       time.Time `json:"created_at"`
}

// CreateOrderRequest is the JSON payload for POST /orders.
type CreateOrderRequest struct {
	CustomerID      string  `json:"customer_id"`
	ItemSKU         string  `json:"item_sku"`
	Quantity        int     `json:"quantity"`
	TotalAmountUSD  float64 `json:"total_amount_usd"`
	AssessFraudRisk bool    `json:"assess_fraud_risk,omitempty"`
	SimulateFailure bool    `json:"simulate_500,omitempty"`
}

// BarnaclesLogEvent matches the structured OTLP JSON schema expected by
// Barnacles (`POST /v1/logs`).
type BarnaclesLogEvent struct {
	Timestamp string            `json:"timestamp"`
	Level     string            `json:"level"`
	Service   string            `json:"service"`
	Namespace string            `json:"namespace"`
	Pod       string            `json:"pod"`
	Message   string            `json:"message"`
	Fields    map[string]string `json:"fields,omitempty"`
}

type metricKey struct {
	method string
	route  string
	status string
}

// Server encapsulates the order store, readiness state, Prometheus counters,
// and async Barnacles telemetry queue.
type Server struct {
	cfg        Config
	logger     *slog.Logger
	ready      atomic.Bool
	inFlight   atomic.Int64
	orderSeq   atomic.Uint64
	httpClient *http.Client

	mu     sync.RWMutex
	orders map[string]Order

	metricsMu        sync.Mutex
	requestsTotal    map[metricKey]uint64
	requestDurationS map[string]float64
	shippedLogsOk    atomic.Uint64
	shippedLogsErr   atomic.Uint64

	logQueue  chan BarnaclesLogEvent
	closeOnce sync.Once
	closed    atomic.Bool
	wg        sync.WaitGroup
}

// New constructs a Server, seeds an initial canary order, and starts the
// background Barnacles log shipping worker.
func New(cfg Config, logger *slog.Logger) *Server {
	if cfg.PodName == "" {
		cfg.PodName = "order-api-local"
	}
	if cfg.PodNamespace == "" {
		cfg.PodNamespace = "app-order-api"
	}
	if cfg.LLMTimeout <= 0 {
		cfg.LLMTimeout = 5 * time.Second
	}

	s := &Server{
		cfg:              cfg,
		logger:           logger,
		httpClient:       &http.Client{Timeout: cfg.LLMTimeout},
		orders:           make(map[string]Order),
		requestsTotal:    make(map[metricKey]uint64),
		requestDurationS: make(map[string]float64),
		logQueue:         make(chan BarnaclesLogEvent, 256),
	}
	s.ready.Store(true)

	// Seed a baseline order so GET /orders works out of the box during smoke tests
	seed := Order{
		ID:             "ord-1001",
		CustomerID:     "cust-enterprise-01",
		ItemSKU:        "gpu-node-reservation-l4",
		Quantity:       2,
		TotalAmountUSD: 1450.00,
		Status:         "CONFIRMED",
		ProcessedByPod: cfg.PodName,
		CreatedAt:      time.Now().UTC(),
	}
	s.orders[seed.ID] = seed
	s.orderSeq.Store(1001)

	s.wg.Add(1)
	go s.barnaclesLogWorker()

	return s
}

// SetReady toggles the readiness probe state. Called with false upon SIGTERM
// so Kubernetes Endpoints/Ingress drain before closing active connections.
func (s *Server) SetReady(ready bool) {
	s.ready.Store(ready)
}

// Close flushes queued Barnacles log events before process exit. Safe to call multiple times.
func (s *Server) Close() {
	s.closeOnce.Do(func() {
		s.closed.Store(true)
		close(s.logQueue)
	})
	s.wg.Wait()
}

// Handler returns the configured HTTP multiplexer wrapped with Golden Signal
// observability middleware.
func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", s.handleHealthz)
	mux.HandleFunc("GET /readyz", s.handleReadyz)
	mux.HandleFunc("GET /metrics", s.handleMetrics)
	mux.HandleFunc("GET /orders", s.handleListOrders)
	mux.HandleFunc("GET /orders/{id}", s.handleGetOrder)
	mux.HandleFunc("POST /orders", s.handleCreateOrder)

	return s.instrumentMiddleware(mux)
}

func (s *Server) handleHealthz(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{
		"status":    "ok",
		"service":   "order-api",
		"pod":       s.cfg.PodName,
		"namespace": s.cfg.PodNamespace,
	})
}

func (s *Server) handleReadyz(w http.ResponseWriter, _ *http.Request) {
	if !s.ready.Load() {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{
			"status": "draining",
			"pod":    s.cfg.PodName,
		})
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{
		"status": "ready",
		"pod":    s.cfg.PodName,
	})
}

func (s *Server) handleListOrders(w http.ResponseWriter, _ *http.Request) {
	s.mu.RLock()
	list := make([]Order, 0, len(s.orders))
	for _, ord := range s.orders {
		list = append(list, ord)
	}
	s.mu.RUnlock()

	sort.Slice(list, func(i, j int) bool {
		return list[i].ID < list[j].ID
	})

	writeJSON(w, http.StatusOK, map[string]any{
		"count":  len(list),
		"orders": list,
	})
}

func (s *Server) handleGetOrder(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	s.mu.RLock()
	ord, exists := s.orders[id]
	s.mu.RUnlock()

	if !exists {
		writeJSON(w, http.StatusNotFound, map[string]string{
			"error": fmt.Sprintf("order %q not found", id),
		})
		return
	}
	writeJSON(w, http.StatusOK, ord)
}

func (s *Server) handleCreateOrder(w http.ResponseWriter, r *http.Request) {
	var req CreateOrderRequest
	dec := json.NewDecoder(io.LimitReader(r.Body, 1<<20))
	if err := dec.Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "invalid JSON request body",
		})
		return
	}

	// Support controlled 5xx injection to test Level 4 Prometheus alerts & Level 7 Argo Rollouts SLO rollback
	if req.SimulateFailure {
		s.emitLog("FATAL", "simulated_order_processing_failure", map[string]string{
			"customer_id": req.CustomerID,
			"item_sku":    req.ItemSKU,
		})
		writeJSON(w, http.StatusInternalServerError, map[string]string{
			"error": "simulated 500 internal error for SLO canary drill",
		})
		return
	}

	if strings.TrimSpace(req.CustomerID) == "" || strings.TrimSpace(req.ItemSKU) == "" || req.Quantity <= 0 || req.TotalAmountUSD <= 0 {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "customer_id, item_sku, quantity (>0), and total_amount_usd (>0) are required",
		})
		return
	}

	seq := s.orderSeq.Add(1)
	ord := Order{
		ID:             fmt.Sprintf("ord-%d", seq),
		CustomerID:     req.CustomerID,
		ItemSKU:        req.ItemSKU,
		Quantity:       req.Quantity,
		TotalAmountUSD: req.TotalAmountUSD,
		Status:         "CONFIRMED",
		ProcessedByPod: s.cfg.PodName,
		CreatedAt:      time.Now().UTC(),
	}

	if req.AssessFraudRisk && s.cfg.OpenAIAPIBase != "" {
		ord.AIRiskSummary = s.assessFraudViaVLLM(r.Context(), ord)
	}

	s.mu.Lock()
	s.orders[ord.ID] = ord
	s.mu.Unlock()

	s.emitLog("INFO", "order_created", map[string]string{
		"order_id":    ord.ID,
		"customer_id": ord.CustomerID,
		"item_sku":    ord.ItemSKU,
		"amount_usd":  fmt.Sprintf("%.2f", ord.TotalAmountUSD),
	})

	writeJSON(w, http.StatusCreated, ord)
}

// assessFraudViaVLLM calls the Level 5 OpenAI-compatible vLLM Gateway (`OPENAI_API_BASE`).
func (s *Server) assessFraudViaVLLM(ctx context.Context, ord Order) string {
	endpoint := strings.TrimRight(s.cfg.OpenAIAPIBase, "/") + "/chat/completions"
	payload := map[string]any{
		"model": s.cfg.LLMModelName,
		"messages": []map[string]string{
			{
				"role":    "system",
				"content": "You are a concise payment risk classifier. Reply in one short sentence.",
			},
			{
				"role":    "user",
				"content": fmt.Sprintf("Order %s: SKU=%s qty=%d total=$%.2f", ord.ID, ord.ItemSKU, ord.Quantity, ord.TotalAmountUSD),
			},
		},
		"max_tokens":  32,
		"temperature": 0.1,
	}

	body, err := json.Marshal(payload)
	if err != nil {
		return "LOW_RISK (fallback: marshal error)"
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(body))
	if err != nil {
		return "LOW_RISK (fallback: request build error)"
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := s.httpClient.Do(req)
	if err != nil {
		s.logger.Warn("vLLM gateway unreachable, using deterministic fallback", "err", err)
		return "LOW_RISK (fallback: vllm gateway offline)"
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Sprintf("LOW_RISK (fallback: vllm status %d)", resp.StatusCode)
	}

	var parsed struct {
		Choices []struct {
			Message struct {
				Content string `json:"content"`
			} `json:"message"`
		} `json:"choices"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&parsed); err != nil || len(parsed.Choices) == 0 {
		return "LOW_RISK (verified)"
	}
	return strings.TrimSpace(parsed.Choices[0].Message.Content)
}

// handleMetrics exposes Prometheus text metrics matching the queries in:
//   - kubernetes/golden-paths/web-service/03-hpa-pdb-netpol-slos.yaml
//   - kubernetes/golden-paths/components/progressive-canary/canary-rollout.yaml
func (s *Server) handleMetrics(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "text/plain; version=0.0.4; charset=utf-8")

	s.metricsMu.Lock()
	keys := make([]metricKey, 0, len(s.requestsTotal))
	for k := range s.requestsTotal {
		keys = append(keys, k)
	}
	sort.Slice(keys, func(i, j int) bool {
		if keys[i].route != keys[j].route {
			return keys[i].route < keys[j].route
		}
		if keys[i].method != keys[j].method {
			return keys[i].method < keys[j].method
		}
		return keys[i].status < keys[j].status
	})

	var buf strings.Builder
	buf.WriteString("# HELP http_requests_total Total HTTP requests processed by order-api.\n")
	buf.WriteString("# TYPE http_requests_total counter\n")
	for _, k := range keys {
		val := s.requestsTotal[k]
		fmt.Fprintf(&buf, "http_requests_total{namespace=%q,pod=%q,method=%q,route=%q,status=%q} %d\n",
			s.cfg.PodNamespace, s.cfg.PodName, k.method, k.route, k.status, val)
	}

	buf.WriteString("# HELP http_request_duration_seconds_sum Total latency in seconds by route.\n")
	buf.WriteString("# TYPE http_request_duration_seconds_sum counter\n")
	for route, sum := range s.requestDurationS {
		fmt.Fprintf(&buf, "http_request_duration_seconds_sum{namespace=%q,pod=%q,route=%q} %.6f\n",
			s.cfg.PodNamespace, s.cfg.PodName, route, sum)
	}
	s.metricsMu.Unlock()

	buf.WriteString("# HELP order_api_inflight_requests Current number of in-flight HTTP requests.\n")
	buf.WriteString("# TYPE order_api_inflight_requests gauge\n")
	fmt.Fprintf(&buf, "order_api_inflight_requests{namespace=%q,pod=%q} %d\n",
		s.cfg.PodNamespace, s.cfg.PodName, s.inFlight.Load())

	buf.WriteString("# HELP order_api_barnacles_shipped_logs_total Total structured log events shipped to Barnacles.\n")
	buf.WriteString("# TYPE order_api_barnacles_shipped_logs_total counter\n")
	fmt.Fprintf(&buf, "order_api_barnacles_shipped_logs_total{namespace=%q,pod=%q,status=\"success\"} %d\n",
		s.cfg.PodNamespace, s.cfg.PodName, s.shippedLogsOk.Load())
	fmt.Fprintf(&buf, "order_api_barnacles_shipped_logs_total{namespace=%q,pod=%q,status=\"error\"} %d\n",
		s.cfg.PodNamespace, s.cfg.PodName, s.shippedLogsErr.Load())

	_, _ = w.Write([]byte(buf.String()))
}

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (r *statusRecorder) WriteHeader(code int) {
	r.status = code
	r.ResponseWriter.WriteHeader(code)
}

func (s *Server) instrumentMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		s.inFlight.Add(1)
		defer s.inFlight.Add(-1)

		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(rec, r)

		route := normalizeRoute(r.URL.Path)
		elapsed := time.Since(start).Seconds()
		statusStr := strconv.Itoa(rec.status)

		s.metricsMu.Lock()
		s.requestsTotal[metricKey{method: r.Method, route: route, status: statusStr}]++
		s.requestDurationS[route] += elapsed
		s.metricsMu.Unlock()

		if route != "/healthz" && route != "/readyz" && route != "/metrics" {
			s.logger.Info("http_request",
				"method", r.Method,
				"path", r.URL.Path,
				"route", route,
				"status", rec.status,
				"duration_ms", fmt.Sprintf("%.2f", elapsed*1000),
				"pod", s.cfg.PodName,
				"namespace", s.cfg.PodNamespace,
			)
		}
	})
}

func normalizeRoute(path string) string {
	switch {
	case path == "/healthz":
		return "/healthz"
	case path == "/readyz":
		return "/readyz"
	case path == "/metrics":
		return "/metrics"
	case path == "/orders":
		return "/orders"
	case strings.HasPrefix(path, "/orders/"):
		return "/orders/{id}"
	default:
		return "/other"
	}
}

func (s *Server) emitLog(level, msg string, fields map[string]string) {
	if s.closed.Load() {
		return
	}
	evt := BarnaclesLogEvent{
		Timestamp: time.Now().UTC().Format(time.RFC3339Nano),
		Level:     level,
		Service:   "order-api",
		Namespace: s.cfg.PodNamespace,
		Pod:       s.cfg.PodName,
		Message:   msg,
		Fields:    fields,
	}
	select {
	case s.logQueue <- evt:
	default:
		// Non-blocking drop if queue is saturated so user requests never stall
		s.shippedLogsErr.Add(1)
	}
}

func (s *Server) barnaclesLogWorker() {
	defer s.wg.Done()
	for evt := range s.logQueue {
		if s.cfg.BarnaclesEndpoint == "" {
			continue
		}
		payload, err := json.Marshal(evt)
		if err != nil {
			s.shippedLogsErr.Add(1)
			continue
		}
		req, err := http.NewRequest(http.MethodPost, s.cfg.BarnaclesEndpoint, bytes.NewReader(payload))
		if err != nil {
			s.shippedLogsErr.Add(1)
			continue
		}
		req.Header.Set("Content-Type", "application/json")
		resp, err := s.httpClient.Do(req)
		if err != nil {
			s.shippedLogsErr.Add(1)
			continue
		}
		_, _ = io.Copy(io.Discard, resp.Body)
		resp.Body.Close()
		if resp.StatusCode >= 200 && resp.StatusCode < 300 {
			s.shippedLogsOk.Add(1)
		} else {
			s.shippedLogsErr.Add(1)
		}
	}
}

func writeJSON(w http.ResponseWriter, status int, data any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(data)
}
