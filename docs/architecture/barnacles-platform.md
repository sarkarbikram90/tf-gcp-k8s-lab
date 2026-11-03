# Project 2 Integration: `Barnacles` Distributed Log Platform & GitOps Delivery

> **Portfolio Objective:** Demonstrate that you can operate a real distributed systems workload on Kubernetes—not simply provision an empty cluster. This architecture integrates [**`Barnacles`**](https://github.com/sarkarbikram90/barnacles) (your Go-based distributed log aggregator with crash-safe edge spooling, Zstandard block storage, OTLP ingestion, and WebSocket live streaming) directly into **`tf-gcp-k8s-lab`**.

---

## 1. Platform Architecture on `tf-gcp-k8s-lab`

```text
                        External Browsers / Operators
                                      │
                                      ▼  HTTPS (:443) + WebSocket Upgrade
                     ┌─────────────────────────────────┐
                     │   Ingress Controller (NGINX)    │
                     │   barnacles.k8s-lab.internal    │
                     └────────────────┬────────────────┘
                                      │  ClusterIP (:8080)
                                      ▼
                     ┌─────────────────────────────────┐
                     │     barnacles-server (SVC)      │
                     └────────┬───────────────┬────────┘
                              │               │
      ┌───────────────────────▼──┐         ┌──▼───────────────────────┐
      │   barnacles-server-0     │◄───────►│   barnacles-server-1     │
      │ (StatefulSet · :8080)    │ xxhash  │ (StatefulSet · :8080)    │
      │ PVC: /app/data/logs 10Gi │ cluster │ PVC: /app/data/logs 10Gi │
      └─────────────▲────────────┘         └────────────▲─────────────┘
                    │  POST /api/v1/ingest (Protobuf/Zstd)
                    │  POST /v1/logs (OTLP/HTTP)
        ┌───────────┴───────────┬───────────────────────┐
        │                       │                       │
┌───────┴────────────┐  ┌───────┴────────────┐  ┌───────┴────────────┐
│ barnacles-agent    │  │ barnacles-agent    │  │ barnacles-agent    │
│ (DaemonSet · Node1)│  │ (DaemonSet · Node2)│  │ (DaemonSet · Node3)│
│ Tails /var/log/pods│  │ Tails /var/log/pods│  │ Tails /var/log/pods│
│ Spool: /agent-spool│  │ Spool: /agent-spool│  │ Spool: /agent-spool│
└────────────────────┘  └────────────────────┘  └────────────────────┘
```

---

## 2. Production Platform Engineering Capabilities Implemented

| Platform Capability | Implementation in [`kubernetes/platform-barnacles/`](../../kubernetes/platform-barnacles/) |
| :--- | :--- |
| **Declarative Kustomize Packaging** | [`kustomization.yaml`](../../kubernetes/platform-barnacles/kustomization.yaml) composes all namespace, RBAC, storage, workload, security, observability, and GitOps manifests with common labels. |
| **Stateful Log Storage (`StatefulSet` + `PVC`)** | [`03-server-statefulset.yaml`](../../kubernetes/platform-barnacles/03-server-statefulset.yaml) runs 2 `barnacles-server` replicas with stable network identities (`barnacles-server-0`, `barnacles-server-1`), anti-affinity across worker nodes, and `10Gi` `volumeClaimTemplates` mounted at `/app/data/logs` for Zstandard block storage and `index.jsonl` manifests. |
| **Edge Log Collection (`DaemonSet` + Downward API)** | [`04-agent-daemonset.yaml`](../../kubernetes/platform-barnacles/04-agent-daemonset.yaml) runs `barnacles-agent` on every node (including control plane nodes via tolerations), injecting `BARNACLES_AGENT_ID` (`metadata.name`) and `BARNACLES_AGENT_HOST` (`spec.nodeName`) via the **Kubernetes Downward API**, tailing `/var/log/pods/**/*.log` with durable disk spooling (`/app/data/agent-spool`). |
| **Externalized Configuration & Secrets** | [`02-configmaps-and-secrets.yaml`](../../kubernetes/platform-barnacles/02-configmaps-and-secrets.yaml) mounts `server.yaml` and `agent.yaml` read-only from a `ConfigMap` and injects `BARNACLES_AUTH_TOKEN` from a Kubernetes `Secret`. |
| **Lifecycle Probes & Graceful Drain** | `startupProbe`, `readinessProbe` (`GET :8080/readyz`), and `livenessProbe` (`GET :8080/healthz`) on `barnacles-server` and `:9090/healthz` on `barnacles-agent`, paired with `preStop` connection drain hooks. |
| **Autoscaling & High Availability (`HPA` + `PDB`)** | [`05-ingress-hpa-pdb-netpol.yaml`](../../kubernetes/platform-barnacles/05-ingress-hpa-pdb-netpol.yaml) scales `barnacles-server` from `2 → 6` replicas on CPU/memory thresholds and guarantees `minAvailable: 1` during node drains (` rolling-upgrade.sh`). |
| **Ingress & WebSocket Streaming** | NGINX `Ingress` configured with WebSocket upgrade timeouts (`proxy-read-timeout: 3600`) for Barnacles' real-time browser streaming hub. |
| **Zero-Trust `NetworkPolicy` & RBAC** | Default-deny isolation in `barnacles` namespace; only `barnacles-agent` pods and the Ingress controller can reach `barnacles-server:8080`, and only `observability` (Prometheus) can scrape `:8080/metrics` and `:9090/metrics`. |
| **Prometheus SLIs, SLOs & Alerts** | [`06-prometheus-barnacles-rules.yaml`](../../kubernetes/platform-barnacles/06-prometheus-barnacles-rules.yaml) tracks ingestion throughput (`events/sec`), edge spool backlog, deduplication ratio, and 5xx ingestion errors. |
| **Argo CD GitOps Delivery** | [`07-argocd-application.yaml`](../../kubernetes/platform-barnacles/07-argocd-application.yaml) continuously reconciles cluster state with `kubernetes/platform-barnacles` in Git (`automated` sync, `selfHeal: true`, `prune: true`). |

---

## 3. Architectural Caveat: Self-Managed `kubeadm` on GCP vs. GKE

As highlighted in the official Kubernetes `kubeadm` HA documentation:
1. **Dynamic `PersistentVolumes` (`CSI`)**: A bare `kubeadm` cluster does not ship with a default `StorageClass` out of the box (unlike GKE's `standard-rwo` backed by `pd.csi.storage.gke.io`). Before deploying `barnacles-server`'s `StatefulSet`:
   - Install the **GCP Compute Engine Persistent Disk CSI Driver** (`gcp-compute-persistent-disk-csi-driver`) for production block storage, OR
   - Install `rancher.io/local-path` (`local-path-provisioner`) as the default `StorageClass` for lab testing (see [Lab 09 (`PVC Pending`)](../labs/lab-09-pvc-pending-storage.md)).
2. **`LoadBalancer` Services**: Without the GCP Cloud Controller Manager (`cloud-provider-gcp`) or MetalLB, `type: LoadBalancer` Services remain `<pending>`. Expose `Barnacles` via `Ingress` + `NodePort` behind your GCP Internal/External TCP Proxy or IAP tunnel (`kubectl port-forward -n barnacles svc/barnacles-server 8080:8080`).

---

## 4. The 10-Step End-to-End Portfolio Demonstration Runbook

Use this sequence during technical interviews or architecture reviews to demonstrate full-stack Platform & SRE ownership:

```bash
# 1. Provision GCP Infrastructure (Terraform)
cd terraform/environments/level2-ha
terraform init -backend-config=backend.hcl && terraform apply -auto-approve

# 2. Bootstrap Highly Available kubeadm Cluster
# (Run 01-install-prereqs.sh & 04-init-ha-control-plane.sh on control plane / workers)

# 3. Deploy Barnacles Platform via Kustomize (or Argo CD GitOps)
kubectl apply -k kubernetes/platform-barnacles/
kubectl rollout status statefulset/barnacles-server -n barnacles --timeout=120s
kubectl rollout status daemonset/barnacles-agent -n barnacles --timeout=120s

# 4. Expose & Verify Live WebSocket Log Dashboard + OTLP Ingestion
kubectl port-forward -n barnacles svc/barnacles-server 8080:8080 &
curl -fsSL http://localhost:8080/healthz
curl -fsSL http://localhost:8080/metrics | head -n 25

# 5. Monitor Application & Cluster Health (Prometheus Rules & Pod Resources)
kubectl apply -f kubernetes/observability/
kubectl get pods,svc,pvc,hpa,pdb,networkpolicy -n barnacles -o wide

# 6. Trigger a Controlled Production Failure (Network Partition Between Agent & Server)
# Apply a temporary deny-all egress policy on barnacles-agent to simulate a central server outage:
kubectl exec -n barnacles ds/barnacles-agent -- ls -la /app/data/agent-spool

# 7. Investigate Root Cause Using SRE Methodology
# Observe barnacles-agent switching automatically to durable local FIFO disk spooling (.inflight lease)
# without dropping a single log event while server connectivity is blocked.
kubectl logs -n barnacles -l app.kubernetes.io/component=agent --tail=30

# 8. Recover the Service & Verify Automatic Spool Drain
# Restore connectivity (or restart a terminated barnacles-server pod) and watch Peek -> Send -> Commit drain:
kubectl delete pod barnacles-server-0 -n barnacles
kubectl get pods -n barnacles -w

# 9. Prove Zero Data Loss Across Pod Recreation
# Verify that barnacles-server-0 re-attaches its 10Gi PVC and retains all Zstd log blocks & index.jsonl!
kubectl exec -n barnacles barnacles-server-0 -- ls -la /app/data/logs

# 10. Document Incident Timeline & Preventive Controls
# Record findings using docs/labs/incident-report-template.md
```
