# `sre-copilot` — Level 7 Autonomous AIOps & CKS Incident Responder (Go)

`sre-copilot` is the Go service backing [`kubernetes/apps/sre-copilot/`](../../kubernetes/apps/sre-copilot/) (`ghcr.io/sarkarbikram90/sre-copilot:v1.1.0`).

It implements the closed-loop incident triage pipeline described in [Level 7 Autonomous Platform](../../docs/architecture/level-7-autonomous-platform.md):
1. Receives inbound webhooks (`POST /webhook`) from **Prometheus Alertmanager** (Level 4) and **Falco Modern eBPF Runtime Defense** ([`01-falco-ebpf-runtime-defense.yaml`](../../kubernetes/security/runtime-security/01-falco-ebpf-runtime-defense.yaml)).
2. Concurrently queries **`Barnacles`** (`BARNACLES_QUERY_ENDPOINT`) and **Prometheus** (`PROMETHEUS_QUERY_ENDPOINT`) using goroutines and `sync.WaitGroup`.
3. Calls the **Level 5 `vLLM` Gateway** (`OPENAI_API_BASE`) to synthesize an actionable Root Cause Analysis (RCA) report (`GET /incidents`).

## Local Verification

```bash
cd services/sre-copilot
go vet ./...
go test -v ./...
```
