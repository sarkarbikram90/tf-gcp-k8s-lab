# `order-api` — Level 6 Golden Path Go Reference Microservice

`order-api` is a zero-dependency, production-hardened Go microservice that backs the [`kubernetes/apps/order-api/`](../../kubernetes/apps/order-api/) Kustomize Golden Path overlay (`ghcr.io/sarkarbikram90/order-api:v1.4.2`).

It demonstrates how a Go service integrates with every layer of `tf-gcp-k8s-lab`:

1. **Level 3 Zero-Trust & Restricted Pod Security Standards (`PSS`)**:
   - Runs as `UID/GID 65532` (`runAsNonRoot: true`) on a `readOnlyRootFilesystem: true` with `allowPrivilegeEscalation: false` and `drop: ["ALL"]` capabilities ([`01-deployment.yaml`](../../kubernetes/golden-paths/web-service/01-deployment.yaml)).
   - Exposes only the L7 HTTP verbs/paths permitted by the Cilium eBPF policy ([`cilium-l7-zero-trust-policy.yaml`](../../kubernetes/security/network-policies/cilium-l7-zero-trust-policy.yaml)).
2. **Level 4 SRE Golden Signals & Prometheus SLOs**:
   - Exposes `http_requests_total{namespace,pod,method,route,status}`, `http_request_duration_seconds_sum`, and `order_api_inflight_requests` on `GET /metrics` (`:8080`), matching the recording and alert rules in [`03-hpa-pdb-netpol-slos.yaml`](../../kubernetes/golden-paths/web-service/03-hpa-pdb-netpol-slos.yaml).
   - Implements immediate readiness drain (`GET /readyz` flips to `503 Service Unavailable` upon `SIGTERM`) so `EndpointSlices` remove the Pod before in-flight HTTP connections close.
3. **Project 2 `Barnacles` Distributed Log Platform**:
   - Ships structured JSON log events asynchronously via a non-blocking bounded channel to `OTEL_EXPORTER_OTLP_LOGS_ENDPOINT` (`http://barnacles-server.barnacles.svc.cluster.local:8080/v1/logs`).
4. **Level 5 `vLLM` AI Inference & Level 7 Argo Rollouts Canary Gate**:
   - Optionally calls the in-cluster `vLLM` OpenAI-compatible gateway (`OPENAI_API_BASE`) on `POST /orders` (`"assess_fraud_risk": true`) with deterministic fallback if the gateway is unreachable.
   - Supports controlled fault injection (`"simulate_500": true`) to test **Argo Rollouts** automated canary rollback ([`canary-rollout.yaml`](../../kubernetes/golden-paths/components/progressive-canary/canary-rollout.yaml)).

---

## HTTP Endpoints

| Method | Path | Purpose |
| :---: | :--- | :--- |
| `GET` | `/healthz` | Kubernetes `startupProbe` and `livenessProbe` (`200 OK`) |
| `GET` | `/readyz` | Kubernetes `readinessProbe` (`200 OK` when ready; `503` during `SIGTERM` drain) |
| `GET` | `/metrics` | Prometheus text-format metrics (`http_requests_total`, latency, in-flight requests, Barnacles log counters) |
| `GET` | `/orders` | List all orders in the in-memory store |
| `GET` | `/orders/{id}` | Retrieve a single order by ID (`ord-1001`, etc.) |
| `POST` | `/orders` | Create a new order (optional `assess_fraud_risk: true` or `simulate_500: true`) |

---

## Local Build, Test & Run

```bash
cd services/order-api

# 1. Run static analysis and unit/integration tests
go vet ./...
go test -v ./...

# 2. Run locally on :8080
go run ./cmd/order-api

# 3. Test endpoints in another terminal
curl -s http://localhost:8080/healthz
curl -s http://localhost:8080/orders
curl -s -X POST http://localhost:8080/orders \
  -H "Content-Type: application/json" \
  -d '{"customer_id":"cust-101","item_sku":"gpu-l4-spot","quantity":2,"total_amount_usd":890.00,"assess_fraud_risk":true}'
curl -s http://localhost:8080/metrics | grep http_requests_total
```

---

## Build Container Image & Deploy via Level 6 Golden Path

```bash
# Build multi-stage non-root container image
docker build -t ghcr.io/sarkarbikram90/order-api:v1.4.2 services/order-api/

# Preview compiled Kubernetes Golden Path manifests
kubectl kustomize kubernetes/apps/order-api

# Apply to cluster
kubectl apply -k kubernetes/apps/order-api
```
