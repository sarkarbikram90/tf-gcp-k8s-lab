# `sre-copilot` — Level 7 Autonomous AIOps & CKS Incident Responder (Go)

`sre-copilot` is the Go service backing [`kubernetes/apps/sre-copilot/`](../../kubernetes/apps/sre-copilot/) (`ghcr.io/sarkarbikram90/sre-copilot:v1.1.0`).

It implements the closed-loop incident triage pipeline described in [Level 7 Autonomous Platform](../../docs/architecture/level-7-autonomous-platform.md):
1. Receives inbound webhooks (`POST /webhook`) from **Prometheus Alertmanager** (Level 4) and **Falco Modern eBPF Runtime Defense** ([`01-falco-ebpf-runtime-defense.yaml`](../../kubernetes/security/runtime-security/01-falco-ebpf-runtime-defense.yaml)).
2. Concurrently queries **`Barnacles`** (`BARNACLES_QUERY_ENDPOINT`), **Prometheus** (`PROMETHEUS_QUERY_ENDPOINT`), and **Kubernetes API Warning Events** (`K8S_API_ENDPOINT` / `/api/v1/namespaces/{ns}/events?fieldSelector=type=Warning`) using goroutines, `sync.WaitGroup`, and the Pod's read-only RBAC ServiceAccount token.
3. Calls the **Level 5 `vLLM` Gateway** (`OPENAI_API_BASE`) to synthesize an actionable Root Cause Analysis (RCA) report (`GET /incidents` and `GET /incidents/{id}`).
4. Exports ready-to-commit **Markdown SRE Post-Mortem Reports** (`GET /incidents/{id}/markdown`) formatted according to [`docs/labs/incident-report-template.md`](../../docs/labs/incident-report-template.md).

## HTTP Endpoints

| Method & Path | Description |
| :--- | :--- |
| `GET /healthz` | Liveness probe (`200 OK`) |
| `GET /readyz` | Readiness probe (`200 OK` or `503 Service Unavailable` during SIGTERM drain) |
| `GET /metrics` | Prometheus metrics (`http_requests_total`, `sre_copilot_rca_reports_total`, `sre_copilot_k8s_event_queries_total`, `sre_copilot_markdown_exports_total`) |
| `POST /webhook` | Accepts Prometheus Alertmanager or Falco CKS JSON alerts and runs 3-way telemetry correlation + `vLLM` RCA synthesis |
| `GET /incidents` | Lists all synthesized `IncidentReport` JSON payloads |
| `GET /incidents/{id}` | Retrieves a specific `IncidentReport` by ID (`inc-1`, `inc-2`, ...) |
| `GET /incidents/{id}/markdown` | Exports the incident as a structured Markdown Post-Mortem report (`text/markdown`) |

## Local Verification

```bash
cd services/sre-copilot
go vet ./...
go test -v -race ./...
```
