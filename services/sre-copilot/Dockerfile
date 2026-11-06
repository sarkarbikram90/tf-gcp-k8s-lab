# ==============================================================================
# Multi-Stage Production Dockerfile: `sre-copilot` (Level 7 Autonomous AIOps)
# ==============================================================================
FROM golang:1.23-alpine AS builder

WORKDIR /src

COPY go.mod ./
COPY cmd/ ./cmd/
COPY internal/ ./internal/

RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -trimpath -ldflags="-s -w" -o /out/sre-copilot ./cmd/sre-copilot

FROM alpine:3.20

RUN apk --no-cache add ca-certificates tzdata && \
    addgroup -g 65532 -S nonroot && \
    adduser -u 65532 -S nonroot -G nonroot

WORKDIR /app
COPY --from=builder /out/sre-copilot /app/sre-copilot

USER 65532:65532
EXPOSE 8080

ENTRYPOINT ["/app/sre-copilot"]
