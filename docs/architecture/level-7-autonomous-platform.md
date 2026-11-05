# Level 7: Autonomous AIOps, Progressive Delivery & Cloud-to-Cluster Convergence

## Overview

While Levels 1–6 establish zero-trust infrastructure, HA Kubernetes, SRE fault-injection labs, `Barnacles` distributed logging, `vLLM` model serving, and a self-service Internal Developer Platform (IDP), **Level 7** converges every preceding layer into a **closed-loop, self-verifying platform**:

1. **In-Cluster AI SRE Agent (`sre-copilot`)**: Scaffolded directly on the Level 6 `ai-agent-service` Golden Path (`kubernetes/apps/sre-copilot/`), connecting **Level 4 Prometheus Alerts** + **Project 2 `Barnacles` OTLP Logs** + **Kubernetes API Events** + **Level 5 `vLLM` Inference** to generate automated Root Cause Analysis (RCA) reports.
2. **Progressive Canary Delivery & Automated SLO Rollback**: Extends Level 6 Golden Paths with an Argo Rollouts composable brick (`kubernetes/golden-paths/components/progressive-canary/`) that queries Golden Signal SLOs and `Barnacles` fatal log metrics before promoting releases (`10% → 50% → 100%`).
3. **Kubernetes `Gateway` API & Live `vLLM` Model Canary Splitting**: Adds a `gateway-route` Golden Path brick (`HTTPRoute`) and splits Level 5 `/v1/chat/completions` traffic `90/10` between FP16 and INT4-AWQ quantized `vLLM` pools (`kubernetes/ai-inference/06-gateway-api-canary-split.yaml`) to optimize `$/1M tokens`.
4. **Cloud-to-Cluster Infrastructure Convergence**: Bridges Terraform (`level3-hardened`) and `kubeadm` to stateful and GPU workloads via an opt-in **NVIDIA L4 Spot GPU worker pool** and automated storage/ingress/Cilium eBPF bootstrap (`kubeadm/scripts/06-install-cluster-addons.sh`).
5. **Shift-Left CI Governance & Full-Stack Chaos Labs (`11`–`14`)**: Audits compiled Kustomize overlays in CI (`scripts/platform/verify-platform-policies.sh`) and extends `sre-lab-runner.sh` with 4 new platform chaos scenarios covering `Barnacles`, `vLLM`, Kyverno, and `ExternalSecret`.

---

## Architecture: Closed-Loop Convergence Across All 7 Levels

```text
┌──────────────────────────────────────────────────────────────────────────────────────────┐
│ LEVEL 6 & 7 DEVELOPER GOLDEN PATHS & PROGRESSIVE DELIVERY                                │
│                                                                                          │
│  kubernetes/apps/order-api/                  kubernetes/apps/sre-copilot/                │
│  (AI-Enabled Commerce Service)               (In-Cluster Autonomous SRE Agent)           │
│   • Base: ai-agent-service                    • Base: ai-agent-service                   │
│   • Brick: +external-secret                   • Bricks: +external-secret                 │
│                                                         +progressive-canary (Argo)       │
│                                                         +gateway-route (HTTPRoute)       │
└──────────────┬─────────────────────────────────────────────────────┬─────────────────────┘
               │                                                     │
               ▼                                                     ▼
┌─────────────────────────────────────────┐   ┌────────────────────────────────────────────┐
│ SLO-GATED PROGRESSIVE ROLLOUT (Argo)    │   │ CLOSED-LOOP AI INCIDENT TRIAGE             │
│  10% -> Pause -> 50% -> AnalysisTemplate│   │  1. Alertmanager Webhook fires (Level 4)   │
│  • Queries Prometheus 5xx Error Ratio   │   │  2. Queries Barnacles OTLP Logs (Project 2)│
│  • Queries Barnacles FATAL Log Count    │   │  3. Reads K8s Warning Events (Read RBAC)   │
│  • Auto-rollbacks on SLO breach         │   │  4. Calls vLLM Gateway (Level 5) for RCA   │
└──────────────┬──────────────────────────┘   └──────────────────────┬─────────────────────┘
               └──────────────────────────┬──────────────────────────┘
                                          ▼
┌──────────────────────────────────────────────────────────────────────────────────────────┐
│ INFRASTRUCTURE, NETWORKING & SHARED SERVICES SUBSTRATE (Levels 1–5 + Project 2)          │
│                                                                                          │
│  • Gateway API (HTTPRoute)   : 90/10 Weighted Split (vLLM FP16 vs. AWQ INT4)             │
│  • Barnacles Log Platform    : StatefulSet (10Gi PVCs) + DaemonSet FIFO Edge Spooler     │
│  • Cluster Add-Ons Bootstrap : local-path CSI + ingress-nginx + Cilium eBPF WireGuard    │
│  • Terraform Compute Pool    : 3 CP + 3 CPU Workers + Optional Spot NVIDIA L4 GPU Node   │
└──────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## Component Matrix: How Level 7 Builds on Existing Layers

| Capability | Existing Foundation Built Upon | New Level 7 Implementation |
| :--- | :--- | :--- |
| **`sre-copilot` AI Responder** | Level 4 Prometheus + Project 2 `Barnacles` + Level 5 `vLLM` + Level 6 `ai-agent-service` | [`kubernetes/apps/sre-copilot/`](../../kubernetes/apps/sre-copilot/) |
| **SLO-Gated Canary Rollouts** | Level 6 Golden Path (`03-hpa-pdb-netpol-slos.yaml`) + `Barnacles` metrics | [`kubernetes/golden-paths/components/progressive-canary/`](../../kubernetes/golden-paths/components/progressive-canary/) |
| **Kubernetes `Gateway` API** | 30-Day Networking Lab + Level 5 `vLLM` + Level 6 Scaffolder CLI | [`kubernetes/golden-paths/components/gateway-route/`](../../kubernetes/golden-paths/components/gateway-route/) & [`06-gateway-api-canary-split.yaml`](../../kubernetes/ai-inference/06-gateway-api-canary-split.yaml) |
| **Spot L4 GPU Pool & CSI Add-Ons** | Level 3 Terraform (`compute` module) + `kubeadm` bootstrap scripts | [`terraform/modules/compute/`](../../terraform/modules/compute/) & [`06-install-cluster-addons.sh`](../../kubeadm/scripts/06-install-cluster-addons.sh) |
| **Platform Chaos Labs (`11`–`14`)** | Level 4 `sre-lab-runner.sh` (`01`–`10`) | [`scripts/troubleshooting/sre-lab-runner.sh`](../../scripts/troubleshooting/sre-lab-runner.sh) ([Lab 11](../labs/lab-11-barnacles-spool-partition.md)–[Lab 14](../labs/lab-14-external-secret-sync.md)) |
| **Shift-Left Policy Verifier** | `.github/workflows/security-scan.yml` + Kyverno ClusterPolicies | [`scripts/platform/verify-platform-policies.sh`](../../scripts/platform/verify-platform-policies.sh) |

---

## End-to-End Runbook

### 1. Bootstrap Cluster Add-Ons (Dynamic Storage CSI, Ingress, Gateway API & Optional Cilium eBPF)
```bash
chmod +x kubeadm/scripts/06-install-cluster-addons.sh
./kubeadm/scripts/06-install-cluster-addons.sh --with-gateway-api
```

### 2. Scaffold or Inspect a Canary + Gateway API Golden Path Application
```bash
# Inspect the compiled closed-loop AI SRE responder manifest
kubectl kustomize kubernetes/apps/sre-copilot

# Or scaffold a new service with SLO Canary + Gateway API HTTPRoute + Cloud Secret
./scripts/platform/scaffold-app.sh recommendation-engine \
  --type ai-agent \
  --team ml-platform \
  --image ghcr.io/sarkarbikram90/recommendation-engine:v1.0.0 \
  --with-secret \
  --with-canary \
  --with-gateway-api
```

### 3. Run Shift-Left Policy Verification Locally
```bash
./scripts/platform/verify-platform-policies.sh
```

### 4. Practice Platform Chaos Scenarios (`Labs 11–14`)
```bash
# Lab 11: Barnacles Network Partition & Edge Spool Drain
./scripts/troubleshooting/sre-lab-runner.sh inject 11
./scripts/troubleshooting/sre-lab-runner.sh verify 11

# Lab 12: vLLM Queue Saturation & Readiness Shedding
./scripts/troubleshooting/sre-lab-runner.sh inject 12
./scripts/troubleshooting/sre-lab-runner.sh verify 12

# Lab 13: IDP Governance & Kyverno Hygiene Violations
./scripts/troubleshooting/sre-lab-runner.sh inject 13
./scripts/troubleshooting/sre-lab-runner.sh verify 13

# Lab 14: ExternalSecret & Secret Key Mapping Drift
./scripts/troubleshooting/sre-lab-runner.sh inject 14
./scripts/troubleshooting/sre-lab-runner.sh verify 14
```
