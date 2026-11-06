# Level 3: Security Hardening & Zero-Trust Architecture

## Overview
Level 3 strips away all lab shortcuts to establish strict zero-trust enterprise security boundaries around the self-managed Kubernetes infrastructure.

## Security Controls
1. **Network Boundary**:
   - Zero public IP addresses on all nodes.
   - Elimination of default VPC network; fully isolated custom subnet with private Google access.
   - Outbound traffic strictly brokered via Cloud NAT.
2. **Access Control (IAM & IAP)**:
   - No open port 22 to the world (`0.0.0.0/0`).
   - SSH access requires IAM authentication through Google Cloud Identity-Aware Proxy (IAP) TCP forwarding (`35.235.240.0/20`).
   - OS Login enforced, linking SSH keys to Google Workspace/Cloud Identity and enforcing multi-factor authentication (MFA).
3. **Identity & Secret Separation**:
   - Node runtime service accounts are isolated from deployment service accounts.
   - Application secrets managed externally via Google Cloud Secret Manager, synchronized into pods via Secrets Store CSI Driver or External Secrets Operator.
   - KMS-backed encryption for secrets at rest within etcd (`EncryptionConfig`).
4. **Kubernetes Control Plane Hardening**:
   - API server auditing enabled to export audit trails to Cloud Logging ([`audit-policy.yaml`](../../kubernetes/security/audit-policy.yaml)).
   - Strict Pod Security Standards (`baseline` / `restricted`) enforced by admission controllers ([`restricted-namespace.yaml`](../../kubernetes/security/pod-security-standards/restricted-namespace.yaml)).
   - Default-deny L3/L4 `NetworkPolicies` ([`default-deny-all.yaml`](../../kubernetes/security/network-policies/default-deny-all.yaml)) and **Cilium eBPF L7 HTTP/FQDN Zero-Trust Policies** ([`cilium-l7-zero-trust-policy.yaml`](../../kubernetes/security/network-policies/cilium-l7-zero-trust-policy.yaml)) restricting HTTP verbs/paths, FQDN egress (`*.huggingface.co`), and blocking cloud metadata SSRF (`169.254.169.254/32`).
5. **CKS Runtime Syscall Security (`Falco` Modern eBPF)**:
   - Real-time Linux kernel syscall inspection via **Falco** (`modern_ebpf`) deployed in `security-runtime` ([`01-falco-ebpf-runtime-defense.yaml`](../../kubernetes/security/runtime-security/01-falco-ebpf-runtime-defense.yaml)).
   - Detects interactive container shells, `/etc/shadow` & PKI reads, immutable binary drift, container escape tools (`nsenter`, `containerd.sock`), and unauthorized outbound connections from `vLLM` pods, forwarding alerts directly to `sre-copilot`.
