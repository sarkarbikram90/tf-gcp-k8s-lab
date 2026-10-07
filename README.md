# Self-Managed Kubernetes Reference Platform on GCP (`tf-gcp-k8s-lab`)

[![Terraform](https://img.shields.io/badge/Terraform-1.6%2B-623CE4.svg?logo=terraform)](https://www.terraform.io/)
[![Google Cloud](https://img.shields.io/badge/Google_Cloud-GCP-4285F4.svg?logo=google-cloud)](https://cloud.google.com/)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.31-326CE5.svg?logo=kubernetes)](https://kubernetes.io/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

An open-source, production-oriented reference architecture and learning lab for bootstrapping, securing, operating, and observing self-managed Kubernetes clusters on Google Cloud Platform using **Terraform**, **kubeadm**, and **containerd**.

Designed for **CKA/CKS candidates**, **Site Reliability Engineers (SREs)**, and **Platform Engineers** seeking hands-on mastery over Kubernetes internals, cloud networking, and zero-leak security practices.

---

## Architecture: Progressive 4-Level Roadmap

Instead of isolated tutorials, this repository presents a progressive evolution sharing unified Terraform modules and operational standards:

```
                                ONE REPOSITORY
                                      │
         ┌────────────────────────────┼────────────────────────────┐
         ▼                            ▼                            ▼
    Level 1: CKA Lab             Level 2: HA Cluster          Level 3 & 4: Production
 • 1 CP + 2 Workers           • 3 CP + 3 Workers           • Zero public IPs + IAP + OS Login
 • Single Subnet + NAT        • Stacked etcd quorum        • WIF CI/CD + GCS Remote State
 • Pure kubeadm lifecycle     • Internal LB (:6443)        • etcd Backup & Restore to GCS
 • CNI & CoreDNS validation   • Multi-master joins         • Prometheus / Grafana / Runbooks
```

- **[Level 1: CKA Lab](docs/architecture/level-1-lab.md)**: Foundational 3-node cluster (1 CP, 2 Workers) with private networking and manual/scripted kubeadm bootstrap.
- **[Level 2: High Availability](docs/architecture/level-2-ha.md)**: 3 Control Planes (stacked etcd quorum), 3 Workers, and an Internal TCP Load Balancer.
- **[Level 3: Security Hardening](docs/architecture/level-3-hardening.md)**: Pure private topology, IAP TCP forwarding, OS Login, strict firewalls, and least-privilege IAM.
- **[Level 4: Production Operations](docs/architecture/level-4-production.md)**: Keyless GitHub Actions CI/CD via Workload Identity Federation (WIF), automated etcd backups to GCS, rolling upgrades, and full-stack observability.

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
│   └── security/                       # Hardening manifests
│       ├── encryption-config.yaml      # etcd Secrets Encryption at Rest configuration
│       ├── audit-policy.yaml           # API Server audit logging policy
│       ├── network-policies/           # Default-deny and DNS egress NetworkPolicies
│       └── pod-security-standards/     # Restricted PSS namespace manifest
├── kubeadm/
│   ├── configs/                        # Kubeadm ClusterConfiguration manifests
│   │   └── ha-cluster-config.yaml
│   └── scripts/
│       ├── 01-install-prereqs.sh       # containerd, sysctl, and kubeadm packages
│       ├── 02-init-control-plane.sh    # Single CP init, kubectl setup, Flannel CNI
│       ├── 03-join-worker.sh           # Worker join helper script
│       ├── 04-init-ha-control-plane.sh # HA Primary CP init with --upload-certs
│       └── 05-join-control-plane.sh    # Secondary CP join helper script
├── docs/
│   └── architecture/                   # Architectural specifications for Levels 1–4
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
3. **Default-Deny Network Policies**:
   ```bash
   kubectl apply -f kubernetes/security/network-policies/
   ```
4. **Restricted Pod Security Standards (PSS)**:
   ```bash
   kubectl apply -f kubernetes/security/pod-security-standards/
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

### 4. Hands-on SRE Troubleshooting Labs
Practice diagnosing and solving real-world Kubernetes failure modes:
- **[Lab 01: Broken CNI & Network Diagnostics](docs/labs/lab-01-broken-cni.md)**: Troubleshoot uninitialized network plugins and stuck CoreDNS pods.
- **[Lab 02: etcd Quorum Loss & Recovery](docs/labs/lab-02-etcd-quorum-loss.md)**: Recover write availability after multi-master partitioned consensus failure.
- **[Lab 03: Certificate Expiration & PKI Renewal](docs/labs/lab-03-kubelet-cert-expiry.md)**: Renew expired control plane and Kubelet certificates via `kubeadm certs renew`.
- **[Lab 04: Node DiskPressure & Storage Reclamation](docs/labs/lab-04-node-pressure-disk-full.md)**: Diagnose root volume pressure and prune containerd image caches.

---

### Teardown (Avoid Billing)

```bash
cd terraform/environments/level3-hardened
terraform destroy
```

---

## License
MIT License. See [LICENSE](LICENSE) for details.



