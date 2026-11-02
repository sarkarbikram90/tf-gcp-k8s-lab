# Lab 10: Stuck Deployment Rollouts, Readiness Probes & PDB Deadlocks

## Objective
Diagnose and resolve a production release where:
1. A rolling update (`Deployment`) hangs midway and fails with `ProgressDeadlineExceeded` because a misconfigured **`readinessProbe`** prevents new `ReplicaSet` pods from ever becoming `Ready`.
2. Node maintenance (`kubectl drain`) is blocked by an overly restrictive **`PodDisruptionBudget` (`PDB`)** (`minAvailable` equal to total replica count or `maxUnavailable: 0`).

---

## First-Principles Mental Model
Understand the difference between Kubernetes probes and rollout safety gates:
- **`startupProbe`**: Protects slow-starting applications (e.g., loading ML model weights into memory) by disabling liveness/readiness checks until startup succeeds.
- **`livenessProbe`**: Answers *"Should `kubelet` kill and restart this container?"*
- **`readinessProbe`**: Answers *"Should this Pod be added to Service `EndpointSlices` and count as `Available` during a Deployment rolling update?"*
  - When a `readinessProbe` fails, the container stays `Running` (`0/1 Ready`, `0 Restarts`), so `kubectl logs` may look completely normal!
  - Because `RollingUpdate` honors `maxUnavailable` and `maxSurge`, the `deployment-controller` halts the rollout to prevent taking down the remaining healthy pods from the previous `ReplicaSet`. After `progressDeadlineSeconds`, the Deployment reports `ProgressDeadlineExceeded`.
- **`PodDisruptionBudget` (`PDB`)**: Protects against voluntary evictions (`kubectl drain`). If a Deployment has `3` replicas and its PDB sets `minAvailable: 3` (or `maxUnavailable: 0`), `eviction` API calls are rejected with `Cannot evict pod as it would violate the pod's disruption budget`.

---

## Automated Failure Injection

```bash
./scripts/troubleshooting/sre-lab-runner.sh inject 10
```

---

## Failure Symptoms
1. `kubectl rollout status deployment/inference-gateway -n sre-lab` hangs or reports:
   ```text
   error: deployment "inference-gateway" exceeded its progress deadline
   ```
2. `kubectl get pods -n sre-lab -l app=inference-gateway` shows a mix of old `1/1 Running` pods and new `0/1 Running` pods.
3. Attempting to drain a node fails due to `PodDisruptionBudget` `inference-gateway-pdb`.

---

## Diagnosis Workflow

### Step 1: Inspect Deployment Rollout Status & ReplicaSets
```bash
kubectl rollout status deployment/inference-gateway -n sre-lab
kubectl rollout history deployment/inference-gateway -n sre-lab
kubectl get rs -n sre-lab -l app=inference-gateway
```
Notice that two `ReplicaSets` are active: the old revision holds healthy pods while the new revision has pods stuck at `0/1 Ready`.

### Step 2: Inspect the Unready Pod Events (`readinessProbe`)
```bash
kubectl describe pod -n sre-lab -l app=inference-gateway
```
Look at the `Events` section:
```text
Warning  Unhealthy  kubelet  Readiness probe failed: HTTP probe failed with statuscode: 404 (or connection refused)
```
Inspect the `readinessProbe` in the Deployment spec:
```bash
kubectl get deploy inference-gateway -n sre-lab -o jsonpath='{.spec.template.spec.containers[0].readinessProbe}{"\n"}'
```

### Step 3: Inspect the `PodDisruptionBudget`
```bash
kubectl get pdb -n sre-lab
kubectl describe pdb inference-gateway-pdb -n sre-lab
```
Look at `ALLOWED DISRUPTIONS: 0`. Because `minAvailable: 3` on a 3-replica Deployment allows zero voluntary evictions, `kubectl drain` is deadlocked.

---

## Remediation

### 1. Immediate Rollback OR Fix the Broken `readinessProbe`
In an active production incident, you can first restore full rollout stability via `kubectl rollout undo`, or fix the `readinessProbe` path/port directly (`/` on port `80`):
```bash
kubectl patch deployment inference-gateway -n sre-lab --type='json' -p='[
  {"op": "replace", "path": "/spec/template/spec/containers/0/readinessProbe/httpGet/path", "value": "/"},
  {"op": "replace", "path": "/spec/template/spec/containers/0/readinessProbe/httpGet/port", "value": 80}
]'
kubectl rollout status deployment/inference-gateway -n sre-lab --timeout=60s
```

### 2. Fix the Deadlocked `PodDisruptionBudget`
Update `inference-gateway-pdb` so `maxUnavailable: 1` (or `minAvailable: 2`), allowing one Pod at a time to be safely evicted during node maintenance:
```bash
kubectl apply -f - <<'EOF'
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: inference-gateway-pdb
  namespace: sre-lab
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: inference-gateway
EOF
```
Confirm `ALLOWED DISRUPTIONS` is now `>= 1`:
```bash
kubectl get pdb inference-gateway-pdb -n sre-lab
```

### 3. Verify Recovery
```bash
./scripts/troubleshooting/sre-lab-runner.sh verify 10
```
