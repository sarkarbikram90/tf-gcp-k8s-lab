# Level 5: AI Systems & LLM Inference Infrastructure (`vLLM` on Kubernetes)

## Overview
Level 5 extends `tf-gcp-k8s-lab` into a **production-style Kubernetes LLM Inference Platform**—bridging Platform Engineering, Distributed Systems, and AI Performance/Economics Engineering.

Instead of treating AI as an external API call, Level 5 focuses on the five core infrastructure problems of production AI at scale:
1. **Compute Efficiency**: Maximizing accelerator/CPU utilization via continuous batching and PagedAttention (`vLLM`).
2. **Latency & Throughput**: Measuring and optimizing **Time to First Token (TTFT)** (prefill bound) and **Inter-Token Latency (ITL) / Tokens Per Second (TPS)** (memory-bandwidth decode bound).
3. **Scalability**: Horizontal autoscaling (`HPA`), model-weight caching via `PersistentVolumeClaims`, and gateway connection pooling.
4. **Reliability**: Startup probes tailored for large model weight loading, readiness gates that shed load when request queues saturate, and `PodDisruptionBudgets`.
5. **Token Economics**: Calculating and minimizing **Cost per Million Tokens (`$/1M tokens`)** via Prometheus recording rules.

---

## Reference Architecture

```text
                  Applications / AI Agents
                             │
                             ▼
            ┌─────────────────────────────────┐
            │      LLM Inference Gateway      │
            │  (NGINX / Timeout & Keepalive)  │
            └────────────────┬────────────────┘
                             │  ClusterIP (:8080 -> :8000)
                             ▼
            ┌─────────────────────────────────┐
            │     vllm-engine-svc (:8000)     │
            └───────┬─────────────────┬───────┘
                    │                 │
         ┌──────────▼──────┐   ┌──────▼──────────┐
         │ vLLM Replica 01 │   │ vLLM Replica 02 │
         │ (CPU or L4 GPU) │   │ (CPU or L4 GPU) │
         └──────────┬──────┘   └──────┬──────────┘
                    │                 │
         ┌──────────▼─────────────────▼──────────┐
         │   Model Weight Cache (PVC / Storage)  │
         └───────────────────┬───────────────────┘
                             │  /metrics (OpenMetrics)
                             ▼
            ┌─────────────────────────────────┐
            │   Prometheus + Alertmanager     │
            │  TTFT · TPS · KV Cache · $/1M   │
            └────────────────┬────────────────┘
                             │
                             ▼
            ┌─────────────────────────────────┐
            │  Grafana AI Economics Dashboard │
            └─────────────────────────────────┘
```

---

## Two-Stage Execution Strategy (CPU-First, GPU-Ready)

1. **Stage A: CPU-Compatible Inference Engine (`kubernetes/ai-inference/02-vllm-serving-deployment.yaml`)**
   - Runs immediately on standard `e2-medium` / `e2-standard-2` nodes in `level1-lab`, `level2-ha`, or `level3-hardened` **with zero GPU spend**.
   - Exposes OpenAI-compatible `/v1/models` and `/v1/chat/completions` endpoints alongside real `vllm:*` Prometheus histograms (`vllm:time_to_first_token_seconds`, `vllm:e2e_request_latency_seconds`, `vllm:generation_tokens_total`, `vllm:gpu_cache_usage_perc`, `vllm:num_requests_waiting`).
   - Lets you practice startup/readiness probe tuning, gateway routing, Prometheus SLO alerting, and load testing without burning GPU quota.
2. **Stage B: Production NVIDIA GPU `vLLM` Deployment (`kubernetes/ai-inference/02b-vllm-gpu-deployment.yaml`)**
   - Targets GPU worker nodes (`nvidia.com/gpu: 1`, `cloud.google.com/gke-accelerator: nvidia-l4` or self-managed NVIDIA GPU Operator nodes).
   - Configures `vllm/vllm-openai` with **PagedAttention** (`--gpu-memory-utilization 0.90`), **Chunked Prefill** (`--enable-chunked-prefill`), shared memory `/dev/shm` (`emptyDir: {medium: Memory}` for PyTorch NCCL tensor parallelism), and persistent HuggingFace Hub model weight caching.

---

## Token Economics Formula

The platform continuously evaluates infrastructure efficiency using the **Cost per Million Tokens** equation in Prometheus ([`04-prometheus-inference-rules.yaml`](../../kubernetes/ai-inference/04-prometheus-inference-rules.yaml)):

$$\text{Cost per } 10^6 \text{ Tokens (USD)} = \frac{\text{Cluster Hourly Compute Cost (USD)} / 3600}{\text{Total Generation Throughput (Tokens/sec)}} \times 10^6$$

---

## 9 Engineering Milestones

1. **Deploy Kubernetes Infrastructure**: Provision Level 1, 2, or 3 cluster via Terraform and `kubeadm`.
2. **Deploy Model-Serving Workload**: Apply `01-namespace-and-storage.yaml` and `02-vllm-serving-deployment.yaml`.
3. **Expose Inference via LLM Gateway**: Apply `03-llm-gateway.yaml` with long-lived HTTP keepalive and streaming support.
4. **Implement AI Observability**: Apply `04-prometheus-inference-rules.yaml` to track TTFT, ITL, KV cache usage, and queue depth.
5. **Measure TTFT & Tokens/Sec**: Run `./scripts/ai-inference/benchmark-inference.sh` to measure P50/P95 latency and token throughput.
6. **Load Testing & Horizontal Scaling**: Apply `05-hpa-and-pdb.yaml` and drive concurrent load to observe replica scaling.
7. **Investigate Memory & KV Cache Saturation**: Inspect `vllm:gpu_cache_usage_perc` and container cgroup memory under high concurrency.
8. **Optimize Inference Performance & Cost**: Compare batch concurrency and quantization impact on `$/1M tokens`.
9. **Simulate Failures & Verify Automatic Recovery**: Inject gateway/replica/probe faults and validate zero-downtime recovery.
