# ==============================================================================
# Multi-Stage Production Dockerfile: `order-api` (Level 6 Golden Path Workload)
# ==============================================================================
# Security & SRE Design Notes:
#   • Compiles a statically linked Go binary (`CGO_ENABLED=0`) with stripped
#     debug symbols (`-s -w`) and reproducible paths (`-trimpath`).
#   • Runs strictly as UID/GID 65532 (`nonroot`) with a read-only root
#     filesystem (`readOnlyRootFilesystem: true`) to satisfy Kubernetes
#     Restricted Pod Security Standards (`kubernetes/golden-paths/web-service/`).
#   • Uses minimal Alpine 3.20 runtime so the Golden Path `preStop` lifecycle
#     hook (`["/bin/sh", "-c", "sleep 5"]`) executes cleanly during Pod drain.
# ==============================================================================

# Stage 1: Build statically linked Go binary
FROM golang:1.23-alpine AS builder

WORKDIR /src

COPY go.mod ./
COPY cmd/ ./cmd/
COPY internal/ ./internal/

RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -trimpath -ldflags="-s -w" -o /out/order-api ./cmd/order-api

# Stage 2: Minimal non-root runtime image (UID/GID 65532)
FROM alpine:3.20

RUN apk --no-cache add ca-certificates tzdata && \
    addgroup -g 65532 -S nonroot && \
    adduser -u 65532 -S nonroot -G nonroot

WORKDIR /app
COPY --from=builder /out/order-api /app/order-api

USER 65532:65532
EXPOSE 8080

ENTRYPOINT ["/app/order-api"]
