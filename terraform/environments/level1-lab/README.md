# Level 1: CKA Kubernetes Lab Environment

This environment provisions the infrastructure for a 3-node self-managed Kubernetes cluster:

- **1 Control Plane Node**: `k8s-lab-control-plane` (`e2-standard-2`, 2 vCPU, 8 GB RAM)
- **2 Worker Nodes**: `k8s-lab-worker-01`, `k8s-lab-worker-02` (`e2-medium`, 2 vCPU, 4 GB RAM)
- **Dedicated VPC & Subnet**: `10.10.0.0/24`
- **Cloud NAT**: Provides outbound internet access for private VMs without exposing public IPs.
- **Identity-Aware Proxy (IAP) Firewall**: Restricts SSH ingress to GCP's IAP netblock (`35.235.240.0/20`).
- **Least-Privilege Node IAM**: Custom runtime service account with only logging and monitoring permissions.

---

## Deployment Steps

### 1. Configure Backend & Variables

```bash
cd terraform/environments/level1-lab

# Configure Remote State (from bootstrap/)
cp backend.hcl.example backend.hcl
# Edit backend.hcl with your state bucket name

# Configure Variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your GCP project_id and preferred region/zone
```

### 2. Provision Infrastructure

```bash
# Initialize Terraform with the remote backend
terraform init -backend-config=backend.hcl

# Validate syntax and plan changes
terraform fmt
terraform validate
terraform plan

# Apply infrastructure changes
terraform apply
```

### 3. Connect to Nodes via IAP

Once `terraform apply` finishes, access the VMs keylessly using Google Cloud IAP tunneling:

```bash
# Control Plane
gcloud compute ssh k8s-lab-control-plane --zone=asia-south2-a --tunnel-through-iap

# Workers
gcloud compute ssh k8s-lab-worker-01 --zone=asia-south2-a --tunnel-through-iap
gcloud compute ssh k8s-lab-worker-02 --zone=asia-south2-a --tunnel-through-iap
```

### 4. Bootstrap Kubernetes with kubeadm

Follow the bootstrap scripts in [`kubeadm/scripts/`](../../../kubeadm/scripts/):
1. Run `01-install-prereqs.sh` on **all 3 nodes**.
2. Run `02-init-control-plane.sh` on the **control plane**.
3. Run `03-join-worker.sh` on **worker-01 and worker-02**.

---

## Teardown

To destroy the lab VMs and network to avoid GCP billing when finished:

```bash
terraform destroy
```
