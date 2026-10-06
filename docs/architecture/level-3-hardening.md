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
   - API server auditing enabled to export audit trails to Cloud Logging.
   - Strict Pod Security Standards (`baseline` / `restricted`) enforced by admission controllers.
   - Default-deny NetworkPolicies on critical namespaces.
