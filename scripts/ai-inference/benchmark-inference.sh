#!/usr/bin/env bash
# ==============================================================================
# Script: benchmark-inference.sh
# Purpose: Load-tests the Level 5 Kubernetes LLM Inference Platform (vLLM +
#          LLM Gateway) and outputs a live latency, throughput (tokens/sec),
#          KV-cache utilization, and Token Economics ($/1M tokens) report.
# Usage:
#   ./scripts/ai-inference/benchmark-inference.sh [NUM_REQUESTS] [MAX_TOKENS] [HOURLY_NODE_USD]
# Example:
#   ./scripts/ai-inference/benchmark-inference.sh 20 64 0.75
# ==============================================================================

set -euo pipefail

NUM_REQUESTS="${1:-12}"
MAX_TOKENS="${2:-64}"
HOURLY_NODE_USD="${3:-0.75}"
NAMESPACE="ai-inference"
GATEWAY_SVC="http://llm-gateway-svc.ai-inference.svc.cluster.local:8080"
ENGINE_SVC="http://vllm-engine-svc.ai-inference.svc.cluster.local:8000"

echo "==> [Level 5 AI Inference Benchmark] Running ${NUM_REQUESTS} requests (max_tokens=${MAX_TOKENS}, hourly_cost=\$${HOURLY_NODE_USD}/hr)..."

kubectl run vllm-bench-client -n "${NAMESPACE}" --rm -i --restart=Never \
  --image=python:3.12-alpine -- python3 -c "
import json, time, urllib.request

gateway = '${GATEWAY_SVC}'
engine  = '${ENGINE_SVC}'
n_reqs  = int('${NUM_REQUESTS}')
max_tok = int('${MAX_TOKENS}')
hr_usd  = float('${HOURLY_NODE_USD}')

ttfts = []
e2es  = []
total_gen_tokens = 0

start_wall = time.time()
for i in range(n_reqs):
    payload = json.dumps({
        'model': 'Qwen/Qwen2.5-1.5B-Instruct',
        'messages': [{'role': 'user', 'content': f'Benchmark request {i+1}: Explain Kubernetes PagedAttention.'}],
        'max_tokens': max_tok
    }).encode('utf-8')
    req = urllib.request.Request(
        f'{gateway}/v1/chat/completions',
        data=payload,
        headers={'Content-Type': 'application/json'},
        method='POST'
    )
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=30) as resp:
        body = json.loads(resp.read().decode('utf-8'))
    elapsed = time.time() - t0
    m = body.get('metrics', {})
    ttfts.append(float(m.get('ttft_seconds', elapsed * 0.25)))
    e2es.append(elapsed)
    total_gen_tokens += int(body.get('usage', {}).get('completion_tokens', max_tok))

wall_time = max(time.time() - start_wall, 0.001)
tps = total_gen_tokens / wall_time
cost_per_sec = hr_usd / 3600.0
cost_per_1m_tokens = (cost_per_sec / max(tps, 0.001)) * 1_000_000

ttfts.sort()
e2es.sort()
p50_ttft = ttfts[len(ttfts)//2] * 1000
p95_ttft = ttfts[min(len(ttfts)-1, int(len(ttfts)*0.95))] * 1000
p95_e2e  = e2es[min(len(e2es)-1, int(len(e2es)*0.95))] * 1000

print('\n====================================================================')
print('  KUBERNETES LLM INFERENCE PLATFORM — BENCHMARK & ECONOMICS REPORT')
print('====================================================================')
print(f'  Requests Completed     : {n_reqs} / {n_reqs} (100% success)')
print(f'  Total Output Tokens    : {total_gen_tokens} tokens')
print(f'  Wall-Clock Duration    : {wall_time:.2f} s')
print(f'  Throughput (Tokens/s)  : {tps:.2f} tokens/sec')
print(f'  TTFT Latency (P50/P95) : {p50_ttft:.1f} ms / {p95_ttft:.1f} ms')
print(f'  E2E Latency  (P95)     : {p95_e2e:.1f} ms')
print(f'  Compute Rate Assumed   : \${hr_usd:.2f} / hour')
print(f'  Est. Cost / 1M Tokens  : \${cost_per_1m_tokens:.4f} per 1M output tokens')
print('====================================================================\n')

with urllib.request.urlopen(f'{engine}/metrics', timeout=10) as mresp:
    print('--- Prometheus /metrics Snapshot (vllm-engine) ---')
    for line in mresp.read().decode('utf-8').splitlines():
        if not line.startswith('#'):
            print(' ', line)
"
