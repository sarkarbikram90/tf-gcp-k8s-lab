# Lab 12: Level 5 AI Inference — `vLLM` Queue Saturation & Readiness Probe Shedding

## Objective
Diagnose and resolve a **[Level 5 AI Inference](../architecture/level-5-ai-inference.md)** outage where:
1. All `vLLM` model-serving replicas (`vllm-serving-sim`) report `0/1 Ready`, causing `vllm-sim-svc` to have zero active endpoints and the LLM Gateway to return `503 Service Unavailable`.
2. The continuous batching concurrency limit (`MAX_NUM_SEQS`) is misconfigured to `0`, starving token generation throughput (`Tokens/sec`) and driving **Cost per 1 Million Tokens (`$/1M tokens`)** toward infinity.

---

## First-Principles Mental Model
In production LLM serving with `vLLM`:
- **Readiness Gates & Load Shedding**: Unlike stateless web apps, LLM inference engines load multi-gigabyte weights into GPU/CPU memory (`startupProbe`) and expose `/health` on the OpenAI serving port. If `readinessProbe` targets the wrong port, `kubelet` removes all replicas from `EndpointSlices`.
- **Continuous Batching (`MAX_NUM_SEQS`)**: `vLLM` PagedAttention amortizes memory-bandwidth decode overhead by batching concurrent sequences (`MAX_NUM_SEQS`, typically `16`–`256`). Setting `MAX_NUM_SEQS` too low starves batching efficiency; setting it too high without sufficient KV-cache headroom triggers request queue buildup (`vllm:num_requests_waiting`).

---

## Automated Failure Injection

```bash
./scripts/troubleshooting/sre-lab-runner.sh inject 12
```

---

## Failure Symptoms
1. `kubectl get pods -n sre-lab -l app=vllm-serving-sim` shows `0/1 Running`.
2. `kubectl get endpoints vllm-sim-svc -n sre-lab` shows `<none>`.

---

## Diagnosis Workflow

### Step 1: Inspect Pod Events & Readiness Probe Configuration
```bash
kubectl describe pod -n sre-lab -l app=vllm-serving-sim
kubectl get deploy vllm-serving-sim -n sre-lab -o jsonpath='{.spec.template.spec.containers[0].readinessProbe}{"\n"}'
```
Notice `readinessProbe` checks port `8009`, while the container listens on port `80` (`http-openai`).

### Step 2: Inspect `vLLM` Batching Environment Variables
```bash
kubectl get deploy vllm-serving-sim -n sre-lab -o jsonpath='{.spec.template.spec.containers[0].env}{"\n"}'
```
Notice `MAX_NUM_SEQS` is set to `"0"`.

---

## Remediation

### 1. Fix `readinessProbe` Port and Tune `MAX_NUM_SEQS` (`>= 16`)
```bash
kubectl patch deployment vllm-serving-sim -n sre-lab --type='json' -p='[
  {"op": "replace", "path": "/spec/template/spec/containers/0/readinessProbe/httpGet/port", "value": 80},
  {"op": "replace", "path": "/spec/template/spec/containers/0/env/0/value", "value": "32"}
]'
kubectl rollout status deployment/vllm-serving-sim -n sre-lab --timeout=60s
```

### 2. Verify Recovery
```bash
./scripts/troubleshooting/sre-lab-runner.sh verify 12
```
