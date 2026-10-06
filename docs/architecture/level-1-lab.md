# Level 1: CKA Kubernetes Lab Architecture

## Overview
Level 1 provides an ephemeral, cost-efficient 3-node Kubernetes cluster on Google Cloud Platform designed specifically for studying and mastering Kubernetes internals (CKA/CKS/CKAD preparation).

```
                            GCP VPC (k8s-lab-vpc)
                            Subnet: 10.10.0.0/24
                                     │
                 ┌───────────────────┼───────────────────┐
                 │                   │                   │
                 ▼                   ▼                   ▼
        k8s-lab-control-plane  k8s-lab-worker-01   k8s-lab-worker-02
         (e2-standard-2)        (e2-medium)         (e2-medium)
          2 vCPU / 8 GB        2 vCPU / 4 GB       2 vCPU / 4 GB
         Ubuntu 24.04 LTS     Ubuntu 24.04 LTS    Ubuntu 24.04 LTS
                 │                   │                   │
                 └───────────────────┼───────────────────┘
                                     │
                             Outbound Egress Only
                                     ▼
                            Cloud NAT & Router
                                     ▼
                              Internet (pkgs.k8s.io, registry.k8s.io)
```

## Security Invariants
1. **Zero Public IPs**: All compute instances have only private RFC1918 internal IPs.
2. **Keyless SSH Administration**: SSH access is exclusively allowed via GCP Identity-Aware Proxy (IAP) TCP forwarding (`35.235.240.0/20`), authenticating against Google IAM and OS Login.
3. **Outbound Internet Egress**: Cloud NAT allows apt and container image pulls without exposing ingress listening ports.
4. **Least-Privilege Node IAM**: Custom runtime service account with only Cloud Logging and Cloud Monitoring scopes.

## Cluster Specifications
- **Kubernetes Version**: `v1.31`
- **Container Runtime**: `containerd` with `SystemdCgroup = true`
- **Pod Network CIDR**: `10.244.0.0/16`
- **CNI**: Flannel (VXLAN overlay)
- **Control Plane Stack**:
  - `kube-apiserver` (port 6443)
  - `etcd` (ports 2379, 2380)
  - `kube-controller-manager`
  - `kube-scheduler`
  - `kube-proxy`
  - `coredns`
