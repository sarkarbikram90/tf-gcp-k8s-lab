# Level 2: High Availability (HA) Kubernetes Environment

This environment provisions a multi-master High Availability self-managed Kubernetes cluster:

- **3 Control Plane Nodes**: `k8s-ha-cp-01`, `k8s-ha-cp-02`, `k8s-ha-cp-03` (`e2-standard-2`, 2 vCPU, 8 GB RAM) distributed across multiple availability zones.
- **3 Worker Nodes**: `k8s-ha-worker-01`, `k8s-ha-worker-02`, `k8s-ha-worker-03` (`e2-medium`, 2 vCPU, 4 GB RAM).
- **Internal TCP Load Balancer**: Regional load balancer fronting the Kubernetes API server (`:6443`) on a static internal IP (`10.10.0.100`).
- **Health Checks**: TCP probe on port 6443 routing traffic only to healthy control plane nodes.
- **Dedicated VPC & Subnet**: `10.10.0.0/24`.
- **Cloud NAT**: Provides outbound internet egress for private VMs without public IPs.
- **Identity-Aware Proxy (IAP) Tunneling**: Zero-exposure administrative SSH access.

---

## Deployment Steps

### 1. Configure Backend & Variables

```bash
cd terraform/environments/level2-ha

# Configure Remote State
cp backend.hcl.example backend.hcl
# Edit backend.hcl: set bucket name from bootstrap/

# Configure Variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: set project_id and region/zones
```

### 2. Deploy Infrastructure

```bash
terraform init -backend-config=backend.hcl
terraform fmt
terraform validate
terraform plan
terraform apply
```

Note the output `api_endpoint` (e.g. `10.10.0.100:6443`).

---

## Bootstrapping the HA Cluster

### 1. Prepare Nodes
Run `kubeadm/scripts/01-install-prereqs.sh` on **all 6 nodes**.

### 2. Initialize Primary Control Plane (`cp-01`)
SSH to `k8s-ha-cp-01`:
```bash
gcloud compute ssh k8s-ha-cp-01 --zone=asia-south2-a --tunnel-through-iap
```
Run `kubeadm/scripts/04-init-ha-control-plane.sh`:
```bash
./04-init-ha-control-plane.sh 10.10.0.100:6443
```
This initializes the cluster with `--control-plane-endpoint="10.10.0.100:6443"`, enables `--upload-certs`, and prints:
- `join-control-plane` command (with certificate key)
- `join-worker` command

### 3. Join Secondary Control Planes (`cp-02` and `cp-03`)
Run the control-plane join command on `cp-02` and `cp-03`.

### 4. Join Worker Nodes (`worker-01`, `worker-02`, `worker-03`)
Run the worker join command on all 3 worker nodes.

### 5. Verify Quorum & Load Balancing
On `cp-01`:
```bash
kubectl get nodes -o wide
kubectl get pods -n kube-system -l component=etcd
```

All 6 nodes should report `Ready`, and etcd will show 3 healthy members forming a quorum.
