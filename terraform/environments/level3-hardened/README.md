# Level 3: Security Hardening & Zero-Trust Environment

This environment provisions an enterprise-hardened self-managed Kubernetes infrastructure implementing strict zero-trust principles:

- **Strict Network Segmentation**: Port-level ingress rules (no open subnet traffic). etcd is restricted exclusively to control plane nodes; Kubelet API access is limited to the control plane.
- **Zero Public IPs**: All 6 nodes are RFC1918 private instances.
- **Zero Public SSH**: SSH access requires IAM authentication via Google Cloud Identity-Aware Proxy (IAP) and OS Login.
- **Cloud KMS Integration**: Provisioned KMS KeyRing and CryptoKey with automated 90-day rotation for encrypting Kubernetes secrets at rest.
- **Google Secret Manager**: Enterprise external secret store with IAM-controlled access for runtime pods via External Secrets Operator or CSI.
- **Regional Internal Load Balancer**: High availability control-plane endpoint (`10.10.0.100:6443`).

---

## Deployment Steps

```bash
cd terraform/environments/level3-hardened

# Configure Remote State
cp backend.hcl.example backend.hcl
# Edit backend.hcl with state_bucket_name from bootstrap/

# Configure Variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with project_id and region/zones

# Initialize & Deploy
terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

---

## Applying Kubernetes In-Cluster Hardening

Once the nodes are provisioned, apply the security manifests located in [`kubernetes/security/`](../../../kubernetes/security/):

1. **etcd Secrets Encryption at Rest**:
   Place [`kubernetes/security/encryption-config.yaml`](../../../kubernetes/security/encryption-config.yaml) in `/etc/kubernetes/enc/` on all control plane nodes before running `kubeadm init`.
2. **API Server Audit Logging**:
   Place [`kubernetes/security/audit-policy.yaml`](../../../kubernetes/security/audit-policy.yaml) in `/etc/kubernetes/audit/` to capture security audit trails.
3. **Network Policies**:
   Apply default-deny policies:
   ```bash
   kubectl apply -f ../../../kubernetes/security/network-policies/
   ```
4. **Pod Security Standards (PSS)**:
   Enforce restricted PSS profiles on tenant namespaces:
   ```bash
   kubectl apply -f ../../../kubernetes/security/pod-security-standards/
   ```
