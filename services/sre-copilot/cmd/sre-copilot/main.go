// Command sre-copilot runs the Level 7 In-Cluster Autonomous SRE Responder.
package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
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
