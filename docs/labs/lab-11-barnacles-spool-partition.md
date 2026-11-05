# Lab 11: Barnacles Log Platform — Network Partition & Edge Spool Drain Recovery

## Objective
Diagnose and resolve a distributed log aggregation incident modeled after [**`Barnacles`**](../architecture/barnacles-platform.md) where:
1. Edge log agents (`barnacles-agent-sim`) cannot ship log batches to the central log server (`barnacles-ingest-svc:8080`) due to a restrictive egress **`NetworkPolicy`** that blocks CoreDNS (`53`) and targets the wrong ingestion port (`9999`).
2. Edge agents automatically fall back to local durable FIFO disk spooling (`/app/data/agent-spool/*.inflight`), and you must heal the network partition and verify that the `.inflight` spool drains cleanly with zero data loss.

---

## First-Principles Mental Model
In a production distributed log pipeline (`DaemonSet` edge shippers → `StatefulSet` central indexers):
- Network partitions and central server rolling restarts are inevitable.
- Instead of dropping logs when `POST /api/v1/ingest` fails, `barnacles-agent` writes compressed batches to a local disk spool (`/app/data/agent-spool/batch-XXXX.inflight`) using a **Peek → Send → Commit** lease protocol.
- When an egress `NetworkPolicy` is applied to a Pod (`policyTypes: ["Egress"]`), **all outbound traffic not explicitly permitted is dropped**—including UDP/TCP `53` to `kube-system` (`CoreDNS`).

---

## Automated Failure Injection

```bash
./scripts/troubleshooting/sre-lab-runner.sh inject 11
```

---

## Failure Symptoms
1. `kubectl logs -n sre-lab deploy/barnacles-agent-sim` repeatedly logs:
   ```text
   [barnacles-agent] Central server unreachable; spooling batch to /app/data/agent-spool/batch-0001.inflight
   ```
2. `kubectl exec -n sre-lab deploy/barnacles-agent-sim -- ls -la /app/data/agent-spool` shows undrained `.inflight` batch files accumulating on disk.

---

## Diagnosis Workflow

### Step 1: Inspect Agent Logs & Local Spool Directory
```bash
kubectl logs -n sre-lab deploy/barnacles-agent-sim --tail=20
kubectl exec -n sre-lab deploy/barnacles-agent-sim -- ls -la /app/data/agent-spool
```

### Step 2: Check Service Port & Active NetworkPolicies
```bash
kubectl get svc barnacles-ingest-svc -n sre-lab
kubectl describe networkpolicy barnacles-agent-partition-lock -n sre-lab
```
Notice two critical defects in `barnacles-agent-partition-lock`:
1. No egress rule permits DNS resolution (`UDP/TCP 53` to `kube-system`).
2. Egress to `barnacles-server-sim` allows TCP port `9999`, whereas `barnacles-ingest-svc` listens on Service port `8080` (`targetPort: 80`).

---

## Remediation

### 1. Patch the Egress `NetworkPolicy` to Permit CoreDNS and Ingest Port (`80`/`8080`)
```bash
kubectl apply -n sre-lab -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: barnacles-agent-partition-lock
spec:
  podSelector:
    matchLabels:
      app: barnacles-agent-sim
  policyTypes:
    - Egress
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
    - to:
        - podSelector:
            matchLabels:
              app: barnacles-server-sim
      ports:
        - protocol: TCP
          port: 80
        - protocol: TCP
          port: 8080
EOF
```

### 2. Verify Spool Drain & Zero Data Loss
Wait 5 seconds for the next retry loop and confirm `.inflight` files have been committed and removed:
```bash
kubectl logs -n sre-lab deploy/barnacles-agent-sim --tail=5
./scripts/troubleshooting/sre-lab-runner.sh verify 11
```
