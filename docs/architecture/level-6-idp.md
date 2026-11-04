# Level 6: Internal Developer Platform (IDP) & Self-Service Golden Paths

## Overview

Levels 1 through 5 of `tf-gcp-k8s-lab` establish a zero-trust, highly available, observable Kubernetes and AI inference platform. However, raw Kubernetes imposes a heavy **cognitive load** on application developers: shipping a single production service like [`Barnacles`](barnacles-platform.md) requires authoring 6–7 separate YAML manifests (`Namespace`, `ServiceAccount`, `Deployment`/`StatefulSet`, `Service`, `Ingress`, `HPA`, `PDB`, `NetworkPolicy`, `PrometheusRule`, and `Argo CD Application`) while navigating strict `restricted` Pod Security Standards and GCP Secret Manager IAM bindings.

**Level 6** evolves the project into an **Internal Developer Platform (IDP)** built on a clear contract:
> **Give developers a frictionless, 20-line self-service Golden Path to build, deploy, and manage applications—without surrendering the zero-trust security, reliability, and FinOps guardrails platform engineers require.**

---

## Architecture: Two-Plane Platform Design

```text
┌──────────────────────────────────────────────────────────────────────────────────────┐
│ 1. DEVELOPER EXPERIENCE PLANE (Low Cognitive Load · Self-Service)                    │
│                                                                                      │
│   $ ./scripts/platform/scaffold-app.sh order-api --type ai-agent --with-secret       │
│                                     │                                                │
│                                     ▼                                                │
│   kubernetes/apps/order-api/                                                         │
│   ├── kustomization.yaml    (Selects Golden Path base + optional Kustomize bricks)   │
│   └── workload-patch.yaml   (20-line intent: image, port, resources, env, host)      │
└─────────────────────────────────────┬────────────────────────────────────────────────┘
                                      │ Git Pull Request / Merge to main
                                      ▼
┌──────────────────────────────────────────────────────────────────────────────────────┐
│ 2. PLATFORM CONTROL PLANE (100% Flexibility & Governance for Platform Engineers)     │
│                                                                                      │
│  ┌────────────────────────────┐  ┌────────────────────────────┐                      │
│  │ Multi-Tenant GitOps        │  │ Golden Path Composition    │                      │
│  │ (Argo CD ApplicationSets)  │  │ (Bases + Components)       │                      │
│  │ • Git Directory Auto-Sync  │  │ • web-service              │                      │
│  │ • PR Ephemeral Previews    │  │ • ai-agent-service (vLLM)  │                      │
│  │ • AppProject RBAC Guard    │  │ • +external-secret / +pvc  │                      │
│  └─────────────┬──────────────┘  └─────────────┬──────────────┘                      │
│                └───────────────┬───────────────┘                                     │
│                                ▼                                                     │
│  ┌────────────────────────────────────────────────────────────┐                      │
│  │ Policy-as-Code & Automated Admission Guardrails (Kyverno)  │                      │
│  │ • MUTATE:   Auto-inject restricted PSS & FinOps labels     │                      │
│  │ • GENERATE: Auto-create NetPol, ResourceQuota & LimitRange │                      │
│  │ • VALIDATE: Block :latest tags, untrusted registries       │                      │
│  └─────────────────────────────┬──────────────────────────────┘                      │
└────────────────────────────────┼─────────────────────────────────────────────────────┘
                                 ▼
┌──────────────────────────────────────────────────────────────────────────────────────┐
│ 3. INFRASTRUCTURE & SHARED SERVICES SUBSTRATE (Levels 1–5)                           │
│  • GCP Secret Manager <-> External Secrets Operator (ClusterSecretStore)             │
│  • Barnacles Distributed Log Platform (Automatic OTLP /var/log/pods ingestion)       │
│  • Level 5 AI Inference Gateway (llm-gateway-svc.ai-inference.svc:8080)              │
│  • Prometheus + Alertmanager Golden Signal SLOs                                      │
└──────────────────────────────────────────────────────────────────────────────────────┘
```

---

## Core Platform Engineering Capabilities

| Pillar | Developer Experience (Simplicity) | Platform Engineering Control (Governance & Flexibility) | Implementation |
| :--- | :--- | :--- | :--- |
| **1. Golden Path Workload Blueprints** | Developers choose a base (`web-service` or `ai-agent-service`) and write a ~20-line patch declaring image, replicas, and route. | Platform engineers own the underlying templates—enforcing non-root `65532` execution, `readOnlyRootFilesystem`, `PodDisruptionBudget`, `HPA`, `NetworkPolicy`, and Prometheus SLO alerts. | [`kubernetes/golden-paths/`](../../kubernetes/golden-paths/) |
| **2. Composable Add-On Bricks** | Developers opt into cloud secrets or persistent disks by adding 1 line under `components:` in `kustomization.yaml`. | Platform engineers define Kustomize `Component`s (`external-secret`, `persistent-storage`) with standardized storage classes and secret refresh intervals. | [`kubernetes/golden-paths/components/`](../../kubernetes/golden-paths/components/) |
| **3. Policy-as-Code that Helps (Kyverno)** | Developers aren't blocked by cryptic Linux security errors; compliant `securityContext` defaults are mutated automatically. | Every tenant namespace automatically receives a synchronized `ResourceQuota`, `LimitRange`, default-deny `NetworkPolicy`, and registry/tag admission checks. | [`kubernetes/platform-idp/kyverno/`](../../kubernetes/platform-idp/kyverno/) |
| **4. Multi-Tenant GitOps & PR Previews** | Merging a folder under `kubernetes/apps/<app>` deploys to production; opening a PR spins up `preview-pr-<id>`. | Argo CD `AppProject` restricts tenant workloads from creating cluster-scoped resources (`ClusterRole`, `Node`, `MutatingWebhookConfiguration`). | [`kubernetes/platform-idp/argocd/`](../../kubernetes/platform-idp/argocd/) |
| **5. Cloud-to-Cluster Secret Sync** | Developers reference secret names via `ExternalSecret`—zero plaintext or placeholder secrets in Git. | `ClusterSecretStore` integrates with Google Cloud Secret Manager ([`terraform/modules/secret-manager`](../../terraform/modules/secret-manager/)) using keyless IAM. | [`kubernetes/platform-idp/external-secrets/`](../../kubernetes/platform-idp/external-secrets/) |
| **6. 1-Command Self-Service CLI** | Run `./scripts/platform/scaffold-app.sh` to scaffold, validate, and preview a production-ready service in seconds. | CLI enforces DNS-1123 naming, warns on mutable `:latest` tags, and validates Kustomize rendering before commit. | [`scripts/platform/scaffold-app.sh`](../../scripts/platform/scaffold-app.sh) |

---

## Before vs. After Level 6: Cognitive Load Reduction

| Dimension | Before Level 6 (Raw Kubernetes) | After Level 6 (IDP Golden Path) |
| :--- | :--- | :--- |
| **Files Authored by Developer** | 6–7 YAML files (`~280+` lines of boilerplate) | 2 files (`kustomization.yaml` + `workload-patch.yaml`, `~25` lines) |
| **Pod Security Standards (`restricted`)** | Manual per container; pod rejected if a field is missed | Pre-configured in Golden Path + auto-mutated by Kyverno |
| **Zero-Trust `NetworkPolicy`** | Hand-written ingress/egress CIDR & namespace selectors | Auto-generated by Kyverno + Golden Path template |
| **Observability & Log Aggregation** | Manual Prometheus rules & OTLP endpoint wiring | Pre-wired to `Barnacles` OTLP collector & Golden Signal alerts |
| **LLM Inference Integration** | Manual service discovery, timeout & keepalive tuning | `ai-agent-service` Golden Path pre-wires `OPENAI_API_BASE` & `NetworkPolicy` to Level 5 `llm-gateway-svc` |
| **Platform Escape Hatch** | N/A | Full Kustomize strategic-merge or JSON6902 patching when custom tuning (e.g., GPUs, custom volumes) is needed |

---

## End-to-End Platform Demonstration Runbook

### 1. Deploy the Platform Control Plane (Platform Engineer)

```bash
# 1. Apply Kyverno Mutating, Generating, and Validating ClusterPolicies
kubectl apply -f kubernetes/platform-idp/kyverno/

# 2. Configure GCP Secret Manager ClusterSecretStore (External Secrets Operator)
kubectl apply -f kubernetes/platform-idp/external-secrets/01-cluster-secret-store.yaml

# 3. Register Multi-Tenant Argo CD AppProjects & ApplicationSets
kubectl apply -f kubernetes/platform-idp/argocd/
```

### 2. Scaffold & Preview a New Application (Application Developer)

```bash
# Scaffold an AI-enabled microservice with GCP Secret Manager integration
./scripts/platform/scaffold-app.sh fraud-detector \
  --type ai-agent \
  --team payments \
  --image ghcr.io/sarkarbikram90/fraud-detector:v1.2.0 \
  --port 8080 \
  --with-secret

# Inspect the compiled 250+ line zero-trust manifest generated from the 25-line overlay
kubectl kustomize kubernetes/apps/fraud-detector
```

### 3. Verify Automated Governance & Escape-Hatch Flexibility

```bash
# Verify reference application renders cleanly
kubectl kustomize kubernetes/apps/order-api

# Commit and push — Argo CD ApplicationSet automatically provisions the isolated
# tenant namespace, triggers Kyverno ResourceQuota/NetworkPolicy generation, and syncs!
```
