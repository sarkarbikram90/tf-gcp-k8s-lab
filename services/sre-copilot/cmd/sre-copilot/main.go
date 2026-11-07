// Command sre-copilot runs the Level 7 In-Cluster Autonomous SRE Responder.
package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/sarkarbikram90/tf-gcp-k8s-lab/services/sre-copilot/internal/copilot"
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	slog.SetDefault(logger)

	cfg := copilot.Config{
		Port:                   envOrDefault("PORT", "8080"),
		PodName:                envOrDefault("POD_NAME", "sre-copilot-local"),
		PodNamespace:           envOrDefault("POD_NAMESPACE", "sre-copilot"),
		BarnaclesQueryEndpoint: os.Getenv("BARNACLES_QUERY_ENDPOINT"),
		PrometheusQueryURL:     os.Getenv("PROMETHEUS_QUERY_ENDPOINT"),
		K8sAPIURL:              resolveK8sAPIURL(),
		K8sBearerToken:         resolveK8sBearerToken(),
		OpenAIAPIBase:          os.Getenv("OPENAI_API_BASE"),
		LLMModelName:           envOrDefault("LLM_MODEL_NAME", "meta-llama/Llama-3.1-8B-Instruct"),
		RCATemplateFormat:      envOrDefault("RCA_TEMPLATE_FORMAT", "sre-incident-report-v1"),
		Timeout:                10 * time.Second,
	}

	srv := copilot.New(cfg, logger)

	httpServer := &http.Server{
		Addr:              ":" + cfg.Port,
		Handler:           srv.Handler(),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       15 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	go func() {
		logger.Info("starting sre-copilot responder", "port", cfg.Port, "pod", cfg.PodName)
		if err := httpServer.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			logger.Error("http server failed", "err", err)
			os.Exit(1)
		}
	}()

	<-ctx.Done()
	srv.SetReady(false)

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	_ = httpServer.Shutdown(shutdownCtx)
}

func envOrDefault(key, fallback string) string {
	if val := os.Getenv(key); val != "" {
		return val
	}
	return fallback
}

func resolveK8sAPIURL() string {
	if val := strings.TrimSpace(os.Getenv("K8S_API_ENDPOINT")); val != "" {
		return val
	}
	host := strings.TrimSpace(os.Getenv("KUBERNETES_SERVICE_HOST"))
	port := strings.TrimSpace(os.Getenv("KUBERNETES_SERVICE_PORT"))
	if host != "" && port != "" {
		return fmt.Sprintf("https://%s:%s", host, port)
	}
	return ""
}

func resolveK8sBearerToken() string {
	if val := strings.TrimSpace(os.Getenv("K8S_BEARER_TOKEN")); val != "" {
		return val
	}
	tokenPath := envOrDefault("K8S_SA_TOKEN_PATH", "/var/run/secrets/kubernetes.io/serviceaccount/token")
	data, err := os.ReadFile(tokenPath)
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(data))
}
