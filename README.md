# Self-Managed Kubernetes Reference Platform on GCP (`tf-gcp-k8s-lab`)

[![Terraform](https://img.shields.io/badge/Terraform-1.6%2B-623CE4.svg?logo=terraform)](https://www.terraform.io/)
[![Google Cloud](https://img.shields.io/badge/Google_Cloud-GCP-4285F4.svg?logo=google-cloud)](https://cloud.google.com/)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.31-326CE5.svg?logo=kubernetes)](https://kubernetes.io/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

An open-source, production-oriented reference architecture and learning lab for bootstrapping, securing, operating, and observing self-managed Kubernetes clusters on Google Cloud Platform using **Terraform**, **kubeadm**, and **containerd**.

Designed for **CKA/CKS candidates**, **Site Reliability Engineers (SREs)**, and **Platform Engineers** seeking hands-on mastery over Kubernetes internals, cloud networking, and zero-leak security practices.

---

## Architecture: Progressive 7-Level Roadmap

Instead of isolated tutorials, this repository presents a progressive evolution sharing unified Terraform modules, SRE operational standards, AI inference infrastructure, a self-service Internal Developer Platform (IDP), and closed-loop AIOps:

```
                                                    ONE REPOSITORY
                                                          │
     ┌────────────────────┬───────────────────┬───────────┴───────────┬────────────────────┬────────────────────┐
     ▼                    ▼                   ▼                       ▼                    ▼                    ▼
Level 1: CKA Lab    Level 2: HA Cluster  Level 3 & 4: Prod SRE   Level 5: AI Engine   Project 2: Barnacles Level 6: IDP Platform
• 1 CP + 2 Workers  • 3 CP + 3 Workers   • Zero Public IPs + IAP • vLLM (CPU / L4 GPU)• Go Log StatefulSet • 20-Line Golden Paths
• Subnet + NAT      • Stacked etcd       • WIF CI/CD + etcd DR   • Streaming Gateway  • Edge Agent Spooler • Kyverno Auto-Guardrails
• Pure kubeadm init • Internal LB :6443  • 10 SRE Fault Labs     • TTFT, TPS & $/1M   • OTLP + WebSockets  • Argo CD AppSets + CLI
```

- **[Level 1: CKA Lab](docs/architecture/level-1-lab.md)**: Foundational 3-node cluster (1 CP, 2 Workers) with private networking and manual/scripted kubeadm bootstrap.
- **[Level 2: High Availability](docs/architecture/level-2-ha.md)**: 3 Control Planes (stacked etcd quorum), 3 Workers, and an Internal TCP Load Balancer.
- **[Level 3: Security Hardening](docs/architecture/level-3-hardening.md)**: Pure private topology, IAP TCP forwarding, OS Login, strict firewalls, least-privilege IAM, and optional Spot NVIDIA L4 GPU worker pool.
- **[Level 4: Production Operations](docs/architecture/level-4-production.md)**: Keyless GitHub Actions CI/CD via Workload Identity Federation (WIF), automated etcd backups to GCS, rolling upgrades, 14-scenario SRE fault injection, and full-stack observability.
- **[Project 2 Platform Workload: `Barnacles` & Argo CD GitOps](docs/architecture/barnacles-platform.md)**: Production Kustomize & Argo CD deployment of [**`Barnacles`**](https://github.com/sarkarbikram90/barnacles) (`StatefulSet` central log server with `10Gi` PVCs + `DaemonSet` edge log collector with Downward API & durable FIFO disk spooling).
- **[Level 5: AI Systems & LLM Inference (`vLLM`)](docs/architecture/level-5-ai-inference.md)**: Production-style Kubernetes LLM Inference Platform with CPU/GPU `vLLM` model serving, Kubernetes `Gateway` API 90/10 canary model splitting, HPA/PDB autoscaling, and Prometheus token economics (`TTFT`, `Tokens/sec`, `$/1M tokens`).
- **[Level 6: Internal Developer Platform (IDP) & Self-Service Golden Paths](docs/architecture/level-6-idp.md)**: Multi-tenant Argo CD `ApplicationSets` (Git directory auto-sync & PR ephemeral preview environments), Kyverno mutating/generating/validating policies, GCP Secret Manager `ExternalSecrets`, composable Kustomize Golden Path blueprints (`web-service`, `ai-agent-service`), and a 1-command developer scaffolding CLI ([`scripts/platform/scaffold-app.sh`](scripts/platform/scaffold-app.sh)).
- **[Level 7: Autonomous AIOps, Progressive Delivery & Cloud-to-Cluster Convergence](docs/architecture/level-7-autonomous-platform.md)**: In-cluster AI SRE responder ([`kubernetes/apps/sre-copilot/`](kubernetes/apps/sre-copilot/)) uniting Level 4 Prometheus alerts, `Barnacles` OTLP logs, and Level 5 `vLLM` inference; Argo Rollouts SLO-gated canary delivery (`progressive-canary`); Kubernetes `Gateway` API `HTTPRoute` bricks; cluster add-ons bootstrap ([`kubeadm/scripts/06-install-cluster-addons.sh`](kubeadm/scripts/06-install-cluster-addons.sh)); and shift-left CI policy verification ([`scripts/platform/verify-platform-policies.sh`](scripts/platform/verify-platform-policies.sh)).
- **[14-Day Kubernetes Engineering Sprint](docs/sprint/README.md)**, **[30-Day Networking Deep Dive](docs/networking/30-day-networking-roadmap.md)** & **[6-Month SRE / Platform / AI Infra Execution Plan (`CKA → CKS`)](docs/sprint/6-month-career-and-execution-plan.md)**: Structured 42-hour first-principles curriculum ([Day 1](docs/sprint/day-01-walkthrough.md), [Day 2](docs/sprint/day-02-walkthrough.md), [Week 1](docs/sprint/days-03-to-07-week1-guide.md), [Week 2 & 90-Day CKA Plan](docs/sprint/days-08-to-14-week2-guide.md)), Linux/CNI packet tracer, and [Engineering Journal Template](docs/sprint/journal-template.md).

---

## Security Invariants (Zero-Leak Contract)

This repository strictly adheres to production-grade security invariants suitable for public open-source code and enterprise clients:

| Security Invariant | How It Is Enforced |
| :--- | :--- |
| **No Service Account JSON Keys** | Local developers use `gcloud auth application-default login` (ADC); CI/CD uses **Workload Identity Federation (WIF)**. |
| **No Static SSH Keys** | All SSH traffic routes through **Google Cloud Identity-Aware Proxy (IAP)** and **OS Login** authenticated by Google IAM. |
| **No Public IPs on Nodes** | VMs have only private internal RFC1918 IPs. Egress (container images, packages) is brokered via **Cloud NAT**. |
| **No Secrets in Terraform** | Kubeadm bootstrap tokens and certificates are generated dynamically at runtime, never stored in Terraform code, state, or metadata. |
| **Encrypted Remote State** | State is isolated in a versioned, IAM-restricted GCS bucket configured in the dedicated `bootstrap/` layer. |

---

## Repository Structure

```text
tf-gcp-k8s-lab/
├── bootstrap/                          # Step 0: GCS state bucket, IAM deployer, WIF pool
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── terraform.tfvars.example
├── terraform/
│   ├── modules/
│   │   ├── network/                    # VPC and custom subnetwork
│   │   ├── nat/                        # Cloud Router and Cloud NAT gateway
│   │   ├── firewall/                   # Fine-grained internal & IAP SSH firewall rules
│   │   ├── compute/                    # Private control plane and worker VM instances
│   │   ├── load-balancer/              # Regional Internal TCP Load Balancer for API server
│   │   ├── iam/                        # Least-privilege node runtime service accounts
│   │   ├── kms/                        # Cloud KMS KeyRing & CryptoKey for secrets encryption
│   │   └── secret-manager/             # Google Secret Manager for external secrets
│   └── environments/
│       ├── level1-lab/                 # Level 1: 1 Control Plane + 2 Workers
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   ├── outputs.tf
│       │   └── terraform.tfvars.example
│       ├── level2-ha/                  # Level 2: 3 Control Planes + 3 Workers + Internal LB
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   ├── outputs.tf
│       │   └── terraform.tfvars.example
│       └── level3-hardened/            # Level 3: Strict Zero-Trust, KMS & Secret Manager
│           ├── main.tf
│           ├── variables.tf
│           ├── outputs.tf
│           └── terraform.tfvars.example
├── kubernetes/
│   ├── ai-inference/                   # Level 5: vLLM engine (CPU/GPU), LLM Gateway, Gateway API Canary, HPA
│   ├── apps/                           # Level 6/7: Tenant workloads (`order-api`, `sre-copilot`)
│   ├── golden-paths/                   # Level 6/7: Golden Path bases & bricks (+secret, +pvc, +canary, +gateway)
│   ├── networking/                     # 30-Day Networking Lab: net-diag DaemonSet, Headless/ClusterIP, Ingress
│   ├── observability/                  # Prometheus alerts and node-exporter DaemonSet
│   ├── platform-barnacles/             # Project 2: Barnacles StatefulSet, DaemonSet, Kustomize & Argo CD GitOps
│   ├── platform-idp/                   # Level 6: Argo CD ApplicationSets, Kyverno policies, External Secrets
│   └── security/                       # Hardening & CKS runtime security manifests
│       ├── encryption-config.yaml      # etcd Secrets Encryption at Rest configuration
│       ├── audit-policy.yaml           # API Server audit logging policy
│       ├── network-policies/           # Default-deny, DNS egress & Cilium L7 eBPF policies
│       ├── pod-security-standards/     # Restricted PSS namespace manifest
│       └── runtime-security/           # CKS Falco modern eBPF syscall detection & AIOps rules
├── kubeadm/
│   ├── configs/                        # Kubeadm ClusterConfiguration manifests
│   │   └── ha-cluster-config.yaml
│   └── scripts/
│       ├── 01-install-prereqs.sh       # containerd, sysctl, and kubeadm packages
│       ├── 02-init-control-plane.sh    # Single CP init, kubectl setup, Flannel CNI
│       ├── 03-join-worker.sh           # Worker join helper script
│       ├── 04-init-ha-control-plane.sh # HA Primary CP init with --upload-certs
│       ├── 05-join-control-plane.sh    # Secondary CP join helper script
│       └── 06-install-cluster-addons.sh# Storage CSI, NGINX Ingress, Gateway API & Cilium eBPF
├── services/
│   ├── order-api/                      # Level 6 Golden Path Go microservice (REST, Prometheus, Barnacles OTLP, vLLM)
│   │   ├── cmd/order-api/main.go
│   │   ├── internal/server/
│   │   ├── Dockerfile
│   │   └── go.mod
│   └── sre-copilot/                    # Level 7 Autonomous AIOps & Falco CKS webhook responder (Go)
│       ├── cmd/sre-copilot/main.go
│       ├── internal/copilot/
│       ├── Dockerfile
│       └── go.mod
├── scripts/
│   ├── ai-inference/                   # vLLM latency, throughput & $/1M token benchmark harness
│   ├── disaster-recovery/              # Automated etcd snapshot backup & restore
│   ├── local/                          # 3-node kind topology & local E2E closed-loop test harness
│   │   ├── kind-config.yaml
│   │   └── kind-e2e-harness.sh
│   ├── networking/                     # End-to-end Linux & Kubernetes packet path tracer
│   ├── operations/                     # Zero-downtime rolling node upgrades
│   ├── platform/                       # Level 6/7: Golden Path scaffolder & shift-left policy verifier
│   │   ├── scaffold-app.sh
│   │   └── verify-platform-policies.sh
│   └── troubleshooting/
│       └── sre-lab-runner.sh           # Automated 14-scenario failure injector & blind drill harness
├── docs/
│   ├── architecture/                   # Architectural specifications for Levels 1–7 & Barnacles platform
│   ├── networking/                     # 30-Day Kubernetes & Linux Networking Deep-Dive Roadmap
│   ├── operations/                     # Day-2 operational runbooks
│   ├── labs/                           # 14-scenario SRE troubleshooting labs & post-mortem template
│   └── sprint/                         # 14-Day Kubernetes Sprint walkthroughs (Days 1–14) & 90-Day CKA Plan
├── Makefile                            # 1-command developer, policy & local kind E2E automation
└── README.md
```

---

## Quickstart: Deploying Level 1 Lab

### Prerequisites
1. [Google Cloud SDK (`gcloud`)](https://cloud.google.com/sdk/docs/install) installed and authenticated.
2. [Terraform (>= 1.6.0)](https://developer.hashicorp.com/terraform/downloads) installed.
3. An active GCP project with billing enabled.

---

### Step 0: Provision Remote State & WIF (`bootstrap/`)

Authenticate locally using Application Default Credentials (ADC):

```bash
gcloud auth login
gcloud auth application-default login
gcloud config set project YOUR_PROJECT_ID
```

Run the bootstrap module:

```bash
cd bootstrap
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: set project_id and state_bucket_name

terraform init
terraform apply
```

Note the output `state_bucket_name` for use in environment backends.

---

### Step 1: Provision Level 1 Infrastructure

Navigate to the `level1-lab` environment:

```bash
cd ../terraform/environments/level1-lab

# Configure remote backend
cp backend.hcl.example backend.hcl
# Edit backend.hcl with the state_bucket_name from Step 0

# Configure variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: set project_id, region, and zone

# Deploy infrastructure
terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

Terraform will create the VPC, subnetwork, Cloud NAT, firewall rules, and the 3 private VMs:
- `k8s-lab-control-plane` (`e2-standard-2`)
- `k8s-lab-worker-01` (`e2-medium`)
- `k8s-lab-worker-02` (`e2-medium`)

---

### Step 2: Bootstrap Kubernetes with kubeadm

#### 1. SSH into the Nodes via IAP Tunneling
Open terminal windows for each node:

```bash
# Terminal 1: Control Plane
gcloud compute ssh k8s-lab-control-plane --zone=YOUR_ZONE --tunnel-through-iap

# Terminal 2: Worker 1
gcloud compute ssh k8s-lab-worker-01 --zone=YOUR_ZONE --tunnel-through-iap

# Terminal 3: Worker 2
gcloud compute ssh k8s-lab-worker-02 --zone=YOUR_ZONE --tunnel-through-iap
```

#### 2. Install Prerequisites on ALL 3 Nodes
On each VM, run:
```bash
curl -fsSL https://raw.githubusercontent.com/sarkarbikram90/tf-gcp-k8s-lab/main/kubeadm/scripts/01-install-prereqs.sh | bash
# Or clone/copy the script directly and run:
chmod +x 01-install-prereqs.sh && ./01-install-prereqs.sh
```

#### 3. Initialize Control Plane
On `k8s-lab-control-plane`:
```bash
chmod +x 02-init-control-plane.sh
./02-init-control-plane.sh
```
This runs `kubeadm init`, configures `$HOME/.kube/config`, applies the Flannel CNI manifest, and saves the worker join command to `$HOME/join-worker.sh`.

#### 4. Join Worker Nodes
Run the join command printed by step 3 on both `k8s-lab-worker-01` and `k8s-lab-worker-02`:
```bash
sudo kubeadm join 10.10.0.X:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>
```

#### 5. Verify Cluster Status
On the Control Plane node:
```bash
kubectl get nodes -o wide
kubectl get pods -A
```
All 3 nodes should report `Ready`, and CoreDNS pods should reach `Running`.

---

---

## Quickstart: Deploying Level 2 (High Availability)

Level 2 scales the lab into a multi-master High Availability cluster with 3 Control Plane nodes (stacked etcd quorum) and 3 Worker nodes, fronted by an Internal Regional TCP Load Balancer on port 6443.

### 1. Provision HA Infrastructure

```bash
cd terraform/environments/level2-ha

# Configure remote backend
cp backend.hcl.example backend.hcl
# Edit backend.hcl with state_bucket_name from bootstrap/

# Configure variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with project_id and zones

# Deploy
terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

Note the `api_endpoint` output (e.g. `10.10.0.100:6443`).

### 2. Bootstrap HA Cluster

1. **Prerequisites**: Run `kubeadm/scripts/01-install-prereqs.sh` on **all 6 nodes**.
2. **Primary Control Plane**: On `k8s-ha-cp-01`:
   ```bash
   ./04-init-ha-control-plane.sh 10.10.0.100:6443
   ```
3. **Secondary Control Planes**: Run the printed control-plane join command on `k8s-ha-cp-02` and `k8s-ha-cp-03`.
4. **Workers**: Run the printed worker join command on `k8s-ha-worker-01`, `k8s-ha-worker-02`, and `k8s-ha-worker-03`.
5. **Verify**:
   ```bash
   kubectl get nodes -o wide
   kubectl get pods -n kube-system -l component=etcd
   ```

---

## Quickstart: Deploying Level 3 (Security Hardening)

Level 3 applies enterprise zero-trust controls: strict port-level network isolation, Cloud KMS secrets encryption at rest, Google Secret Manager integration, API server audit policies, and Pod Security Standards.

### 1. Provision Hardened Infrastructure

```bash
cd terraform/environments/level3-hardened

# Configure remote backend
cp backend.hcl.example backend.hcl

# Configure variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with project_id and region/zones

# Deploy
terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

### 2. Configure In-Cluster Security Controls

1. **etcd Secrets Encryption at Rest**:
   Copy [`kubernetes/security/encryption-config.yaml`](kubernetes/security/encryption-config.yaml) to `/etc/kubernetes/enc/encryption-config.yaml` on all control plane nodes before running `kubeadm init`.
2. **API Server Audit Logging**:
   Copy [`kubernetes/security/audit-policy.yaml`](kubernetes/security/audit-policy.yaml) to `/etc/kubernetes/audit/audit-policy.yaml` on control plane nodes.
3. **Default-Deny & Cilium Layer-7 eBPF Network Policies**:
   ```bash
   # Standard Kubernetes L3/L4 NetworkPolicies
   kubectl apply -f kubernetes/security/network-policies/default-deny-all.yaml
   kubectl apply -f kubernetes/security/network-policies/allow-dns-egress.yaml

   # Cilium eBPF L7 HTTP/FQDN Zero-Trust Policies (when bootstrapped with --with-cilium-ebpf)
   kubectl apply -f kubernetes/security/network-policies/cilium-l7-zero-trust-policy.yaml
   ```
4. **Restricted Pod Security Standards (PSS)**:
   ```bash
   kubectl apply -f kubernetes/security/pod-security-standards/
   ```
5. **CKS Runtime Syscall Security (`Falco` Modern eBPF)**:
   ```bash
   kubectl apply -f kubernetes/security/runtime-security/01-falco-ebpf-runtime-defense.yaml
   ```

---

---

## Quickstart: Level 4 (Production Operations & Observability)

Level 4 operationalizes the cluster with automated disaster recovery, zero-downtime rolling node upgrades, full-stack observability, and hands-on SRE failure-injection labs.

### 1. Automated etcd Disaster Recovery
Run the automated backup script to create an etcd snapshot with SHA256 verification and upload to Google Cloud Storage:

```bash
# Automated snapshot to GCS
sudo ./scripts/disaster-recovery/etcd-backup.sh gs://YOUR_BACKUP_BUCKET

# Disaster recovery restore (if disaster strikes)
sudo ./scripts/disaster-recovery/etcd-restore.sh /var/backups/etcd/etcd-snapshot-YYYYMMDD_HHMMSS.db
```
See the complete [etcd Backup & Restore Runbook](docs/operations/etcd-backup-restore.md).

### 2. Rolling Node Upgrades
Perform sequential minor version upgrades (`1.31` → `1.32`) with automatic draining and package management:

```bash
sudo ./scripts/operations/rolling-upgrade.sh 1.31.1-1.1 control-plane
```
See the complete [Kubernetes Rolling Upgrade Runbook](docs/operations/cluster-upgrades.md).

### 3. Deploy Observability Stack
Deploy Prometheus alerts and node metrics collection:

```bash
kubectl apply -f kubernetes/observability/01-namespace.yaml
kubectl apply -f kubernetes/observability/02-prometheus-alerts.yaml
kubectl apply -f kubernetes/observability/03-node-exporter-daemonset.yaml
```

### 4. Hands-on SRE Troubleshooting Labs (14-Scenario Suite & Automated Fault Injector)

Practice diagnosing and resolving real-world Kubernetes, `Barnacles`, `vLLM`, and IDP failure modes from first principles using the **[SRE Troubleshooting Playbook](docs/labs/README.md)** and automated fault-injection harness ([`scripts/troubleshooting/sre-lab-runner.sh`](scripts/troubleshooting/sre-lab-runner.sh)):

```bash
# Inject a specific failure scenario (01 through 14)
./scripts/troubleshooting/sre-lab-runner.sh inject 11

# Or launch a blind 25-minute on-call drill (random mystery failure)
./scripts/troubleshooting/sre-lab-runner.sh random

# Verify your root-cause fix and elapsed recovery time
./scripts/troubleshooting/sre-lab-runner.sh verify current

# Clean up all fault-injection resources
./scripts/troubleshooting/sre-lab-runner.sh reset all
```

- **[Lab 01: Broken CNI & Network Diagnostics](docs/labs/lab-01-broken-cni.md)**: Troubleshoot uninitialized network plugins and stuck CoreDNS pods.
- **[Lab 02: Control Plane & etcd Quorum Loss](docs/labs/lab-02-etcd-quorum-loss.md)**: Recover write availability after static pod misconfigurations or consensus failure.
- **[Lab 03: Node `NotReady`, Kubelet & PKI Renewal](docs/labs/lab-03-kubelet-cert-expiry.md)**: Diagnose stopped `kubelet` daemons and renew expired X.509 certificates via `kubeadm certs renew`.
- **[Lab 04: Node `DiskPressure` & Storage Reclamation](docs/labs/lab-04-node-pressure-disk-full.md)**: Diagnose ephemeral storage eviction, root volume pressure, and prune `containerd` caches.
- **[Lab 05: `CrashLoopBackOff` & `ImagePullBackOff`](docs/labs/lab-05-crashloop-and-imagepull.md)**: Diagnose invalid image tags, missing `ConfigMap` keys, startup command errors, and broken `livenessProbe` ports.
- **[Lab 06: `Pending` Pods, Scheduling & Affinity](docs/labs/lab-06-pending-pods-scheduling.md)**: Analyze `kube-scheduler` filter predicates, CPU/memory starvation, `Taints`/`Tolerations`, and `nodeSelector` rules.
- **[Lab 07: `OOMKilled` (Exit Code 137) & Memory QoS](docs/labs/lab-07-oomkilled-memory-limits.md)**: Trace Linux kernel cgroup OOM kills (`dmesg`) and right-size limits to achieve `Guaranteed` QoS.
- **[Lab 08: Service Routing, DNS & `NetworkPolicy` Blackholes](docs/labs/lab-08-service-networking-and-dns.md)**: Debug empty `EndpointSlices`, `targetPort` drift, `iptables` rules, and restrictive ingress/DNS egress policies.
- **[Lab 09: `PVC Pending`, `StorageClass` & Persistence](docs/labs/lab-09-pvc-pending-storage.md)**: Resolve unbound `PersistentVolumeClaims`, storage class mismatches, and verify stateful data survival across Pod deletion.
- **[Lab 10: Stuck Rollouts, Readiness Probes & `PDB` Deadlocks](docs/labs/lab-10-stuck-rollout-and-probes.md)**: Recover deployments failing with `ProgressDeadlineExceeded` and unblock `PodDisruptionBudget` node drains.
- **[Lab 11: `Barnacles` Partition & Edge Spool Drain Recovery](docs/labs/lab-11-barnacles-spool-partition.md)**: Heal an egress partition blocking log ingestion and verify durable FIFO `.inflight` spool drain.
- **[Lab 12: `vLLM` Queue Saturation & Readiness Probe Shedding](docs/labs/lab-12-vllm-queue-saturation.md)**: Restore `vLLM` continuous batching (`MAX_NUM_SEQS`) and recover zero-endpoint `503` gateway outages.
- **[Lab 13: IDP Governance & Kyverno Hygiene Violations](docs/labs/lab-13-idp-kyverno-admission.md)**: Remediate a rogue workload violating `:latest` image blocks, FinOps labels, and `restricted` PSS.
- **[Lab 14: `ExternalSecret` & Secret Key Mapping Drift](docs/labs/lab-14-external-secret-sync.md)**: Resolve `CreateContainerConfigError` caused by GCP Secret Manager / Kubernetes `Secret` key drift.
- **[SRE Incident Report Template](docs/labs/incident-report-template.md)**: Standardized post-mortem template for documenting symptoms, hypotheses, evidence, root cause, and preventive actions.

---

## Quickstart: Level 5 (Kubernetes-Based LLM Inference Platform — `vLLM`)

Level 5 deploys an OpenAI-compatible **LLM Inference Platform** on Kubernetes (`ai-inference` namespace) with an NGINX streaming gateway, Prometheus latency/throughput/token-economics recording rules, HPA autoscaling, and a two-stage serving design (**Stage A: CPU-compatible simulator** for zero-GPU-cost learning on standard `e2-medium` nodes; **Stage B: Production NVIDIA L4 GPU `vLLM` engine**).

### 1. Deploy the Inference Stack (CPU-First Mode)

```bash
kubectl apply -f kubernetes/ai-inference/01-namespace-and-storage.yaml
kubectl apply -f kubernetes/ai-inference/02-vllm-serving-deployment.yaml
kubectl apply -f kubernetes/ai-inference/03-llm-gateway.yaml
kubectl apply -f kubernetes/ai-inference/04-prometheus-inference-rules.yaml
kubectl apply -f kubernetes/ai-inference/05-hpa-and-pdb.yaml

# Wait for vLLM engine and LLM Gateway replicas to become Ready
kubectl get pods,svc,hpa,pdb -n ai-inference
```

*(When running on a GPU-enabled node pool with the NVIDIA GPU Operator installed, apply [`kubernetes/ai-inference/02b-vllm-gpu-deployment.yaml`](kubernetes/ai-inference/02b-vllm-gpu-deployment.yaml) instead.)*

### 2. Run Inference Benchmark & Token Economics Report (`$/1M Tokens`)

Execute the automated benchmark script to send OpenAI `/v1/chat/completions` traffic through the LLM Gateway and compute **P50/P95 Time to First Token (TTFT)**, **Tokens/sec**, **KV-Cache Utilization**, and **Cost per 1 Million Output Tokens**:

```bash
./scripts/ai-inference/benchmark-inference.sh 20 64 0.75
```

See the complete [Level 5 AI Inference Architecture Specification](docs/architecture/level-5-ai-inference.md).

---

## Quickstart: Project 2 Integration (`Barnacles` Platform & Argo CD GitOps)

Deploy [**`Barnacles`**](https://github.com/sarkarbikram90/barnacles) (distributed Go log aggregator) as a production platform workload using Kustomize or Argo CD GitOps:

```bash
# Deploy Barnacles StatefulSet (Server + 10Gi PVCs), DaemonSet (Edge Agent), HPA, PDB, NetworkPolicy & Prometheus rules
kubectl apply -k kubernetes/platform-barnacles/

# Or register the declarative Argo CD GitOps Application
kubectl apply -f kubernetes/platform-barnacles/07-argocd-application.yaml
```

See the complete [`Barnacles` Platform Architecture & 10-Step Demonstration Runbook](docs/architecture/barnacles-platform.md).

---

## Quickstart: Level 6 (Internal Developer Platform & Golden Paths)

Level 6 gives developers a **20-line self-service Golden Path** (`web-service` or `ai-agent-service`) while Platform Engineers retain full control via **Kyverno** auto-mutation/generation policies, **External Secrets Operator** (GCP Secret Manager), and multi-tenant **Argo CD `ApplicationSets`**.

### 1. Apply the Platform Control Plane (Platform Engineer)

```bash
# 1. Apply Kyverno mutating (PSS defaults), generating (NetPol/Quota), and validating policies
kubectl apply -f kubernetes/platform-idp/kyverno/

# 2. Register GCP Secret Manager ClusterSecretStore
kubectl apply -f kubernetes/platform-idp/external-secrets/01-cluster-secret-store.yaml

# 3. Register multi-tenant Argo CD AppProjects & ApplicationSets (Git directory + PR previews)
kubectl apply -f kubernetes/platform-idp/argocd/
```

### 2. Scaffold & Onboard a New Application (Application Developer)

```bash
# Scaffold an AI-enabled service wired to Level 5 LLM Gateway, Barnacles OTLP logs,
# GCP Secret Manager, Argo Rollouts SLO Canary, and Gateway API HTTPRoute
./scripts/platform/scaffold-app.sh fraud-detector \
  --type ai-agent \
  --team payments \
  --image ghcr.io/sarkarbikram90/fraud-detector:v1.2.0 \
  --with-secret \
  --with-canary \
  --with-gateway-api

# Preview the compiled zero-trust manifests (`order-api` or `sre-copilot`)
kubectl kustomize kubernetes/apps/order-api
kubectl kustomize kubernetes/apps/sre-copilot

# Run Shift-Left Policy-as-Code verification across all Golden Paths & Tenant Apps
./scripts/platform/verify-platform-policies.sh

# Build & test the Go reference microservices (`services/order-api` & `services/sre-copilot`)
make test

# Run the zero-Docker local E2E closed-loop pipeline (order-api -> sre-copilot -> Markdown Post-Mortem)
make e2e-local

# Or provision a 3-node local kind cluster and run the E2E suite
make kind-e2e
```

See the complete [Level 6 Internal Developer Platform (IDP) Specification](docs/architecture/level-6-idp.md) and [Level 7 Autonomous AIOps & Progressive Delivery Specification](docs/architecture/level-7-autonomous-platform.md).

---

### Teardown (Avoid Billing)

```bash
cd terraform/environments/level3-hardened
terraform destroy
```

---

## License
MIT License. See [LICENSE](LICENSE) for details.



