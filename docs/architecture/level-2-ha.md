# Level 2: High Availability (HA) Kubernetes Architecture

## Overview
Level 2 evolves the cluster from a single point of failure into a production-grade High Availability cluster with 3 Control Plane nodes and stacked etcd, fronted by an Internal TCP Load Balancer.

```
                                  GCP VPC
                                10.10.0.0/24
                                     │
                        Internal TCP Load Balancer
                             Port 6443 (API)
                                     │
           ┌─────────────────────────┼─────────────────────────┐
           ▼                         ▼                         ▼
        k8s-cp-01                 k8s-cp-02                 k8s-cp-03
     kube-apiserver            kube-apiserver            kube-apiserver
       etcd node 1               etcd node 2               etcd node 3
           │                         │                         │
           └─────────────────────────┼─────────────────────────┘
                                     │
                         etcd Quorum (2 of 3 votes)
                                     │
           ┌─────────────────────────┼─────────────────────────┐
           ▼                         ▼                         ▼
      k8s-worker-01             k8s-worker-02             k8s-worker-03
```

## Key Architectural Concepts
1. **Stacked etcd Topology**:
   - Each control plane node runs a local etcd instance as a static pod.
   - An odd number of nodes (3) ensures consensus quorum ($Q = \lfloor n/2 \rfloor + 1 = 2$). The cluster can tolerate losing 1 control plane node without downtime.
2. **Control Plane Endpoint**:
   - Instead of pointing worker nodes to a single VM's IP, `kubeadm init` uses `--control-plane-endpoint="k8s-api.internal:6443"`.
   - The GCP Internal TCP Load Balancer distributes health-checked traffic across all healthy control-plane instances.
3. **Multi-Master Joining & Certificate Distribution**:
   - Secondary control plane nodes join using `kubeadm join ... --control-plane --certificate-key <key>`, leveraging kubeadm's automatic certificate upload and encryption feature.
