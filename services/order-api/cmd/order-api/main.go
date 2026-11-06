// Command order-api runs the Level 6 Golden Path reference microservice.
// It exposes REST endpoints, Prometheus Golden Signal metrics, Barnacles OTLP
// log shipping, Level 5 vLLM fraud-risk enrichment, and graceful SIGTERM drain.
package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"github.com/sarkarbikram90/tf-gcp-k8s-lab/services/order-api/internal/server"
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
		Level: slog.LevelInfo,
	}))
	slog.SetDefault(logger)

	cfg := server.Config{
		Port:              envOrDefault("PORT", "8080"),
		AppEnv:            envOrDefault("APP_ENV", "production"),
		PodName:           envOrDefault("POD_NAME", "order-api-local"),
		PodNamespace:      envOrDefault("POD_NAMESPACE", "app-order-api"),
		BarnaclesEndpoint: os.Getenv("OTEL_EXPORTER_OTLP_LOGS_ENDPOINT"),
		OpenAIAPIBase:     os.Getenv("OPENAI_API_BASE"),
		LLMModelName:      envOrDefault("LLM_MODEL_NAME", "meta-llama/Llama-3.1-8B-Instruct"),
		LLMTimeout:        parseTimeoutSeconds("LLM_REQUEST_TIMEOUT_SECONDS", 10),
	}

	srv := server.New(cfg, logger)

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
		logger.Info("starting order-api server",
			"port", cfg.Port,
			"env", cfg.AppEnv,
			"pod", cfg.PodName,
			"namespace", cfg.PodNamespace,
			"barnacles_endpoint", cfg.BarnaclesEndpoint,
			"openai_api_base", cfg.OpenAIAPIBase,
		)
		if err := httpServer.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			logger.Error("http server failed", "err", err)
			os.Exit(1)
		}
	}()

	<-ctx.Done()
	logger.Info("received termination signal, marking readiness probe unready and draining connections")

	// Mark /readyz as 503 immediately so Kubernetes EndpointSlices drop this Pod
	srv.SetReady(false)

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	if err := httpServer.Shutdown(shutdownCtx); err != nil {
		logger.Error("graceful http shutdown error", "err", err)
	}
	srv.Close()
	logger.Info("order-api shutdown complete")
}

func envOrDefault(key, fallback string) string {
	if val := os.Getenv(key); val != "" {
		return val
	}
	return fallback
}

func parseTimeoutSeconds(key string, fallbackSec int) time.Duration {
	if raw := os.Getenv(key); raw != "" {
		if sec, err := strconv.Atoi(raw); err == nil && sec > 0 {
			return time.Duration(sec) * time.Second
		}
	}
	return time.Duration(fallbackSec) * time.Second
}
