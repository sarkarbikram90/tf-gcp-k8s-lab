# Lab 09: Storage Provisioning Failures (`PVC Pending`, StorageClasses & Volume Affinity)

## Objective
Diagnose and resolve stateful workload failures where a `PersistentVolumeClaim` (`PVC`) remains stuck in `Pending` and blocks a `StatefulSet` or `Deployment` Pod from starting, then prove data persistence across Pod deletion and recreation.

---

## First-Principles Mental Model
Kubernetes storage binding relies on two control loops (**`persistentvolume-controller`** and **CSI external-provisioner**):
1. When a user creates a `PersistentVolumeClaim` (`PVC`) specifying `storageClassName: X`:
   - **Dynamic Provisioning**: The CSI provisioner watching `StorageClass X` dynamically creates a backing volume and a `PersistentVolume` (`PV`) object. If `StorageClass X` does not exist—or has no provisioner installed in a self-managed `kubeadm` cluster—the `PVC` stays `Pending` indefinitely (`storageclass.storage.k8s.io "..." not found` or `waiting for external provisioner`).
   - **`WaitForFirstConsumer` Binding Mode**: Even with a valid `StorageClass`, the `PVC` intentionally stays `Pending` until a Pod mounting the `PVC` is scheduled onto a specific node so topology constraints can be respected.
   - **Static Provisioning**: If `storageClassName` is `manual` (or `""`), the controller looks for an existing `Available` `PV` whose **capacity**, **`accessModes`** (`ReadWriteOnce` vs `ReadWriteMany`), and **`storageClassName`** match the `PVC`.

---

## Automated Failure Injection

```bash
./scripts/troubleshooting/sre-lab-runner.sh inject 09
```

---

## Failure Symptoms
1. `kubectl get pvc -n sre-lab` shows `postgres-data-pvc` stuck in `Pending`.
2. `kubectl get pods -n sre-lab` shows `postgres-db-*` stuck in `Pending` with `unbound immediate PersistentVolumeClaims`.

---

## Diagnosis Workflow

### Step 1: Inspect PVC Status & Events
```bash
kubectl get pv,pvc,storageclass -n sre-lab
kubectl describe pvc postgres-data-pvc -n sre-lab
```
Look at the `Events` output:
- Does the `StorageClass` referenced by `postgres-data-pvc` (`nonexistent-fast-ssd`) exist in `kubectl get storageclass`?
- Is there an `Available` `PersistentVolume` (`sre-lab-pv`) whose `storageClassName` or `accessModes` fails to match the `PVC`?

### Step 2: Compare the Available `PersistentVolume` vs. `PersistentVolumeClaim`
```bash
kubectl get pv sre-lab-pv -o yaml
kubectl get pvc postgres-data-pvc -n sre-lab -o yaml
```
Notice the mismatch:
- `sre-lab-pv` has `storageClassName: local-storage`, `capacity.storage: 1Gi`, and `accessModes: [ReadWriteOnce]`.
- `postgres-data-pvc` requests `storageClassName: nonexistent-fast-ssd`.

---

## Remediation

### 1. Re-create the PVC with Matching `storageClassName` & `accessModes`
Since `spec.storageClassName` on an existing `PVC` is **immutable**, delete and recreate `postgres-data-pvc` so it binds to `sre-lab-pv` (`storageClassName: local-storage`):
```bash
kubectl delete pvc postgres-data-pvc -n sre-lab --wait=false
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-data-pvc
  namespace: sre-lab
spec:
  storageClassName: local-storage
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 500Mi
EOF
```

### 2. Verify PVC Binding & Data Persistence Across Pod Recreation
1. Confirm the `PVC` transitions to `Bound` and `postgres-db` reaches `Running`:
   ```bash
   kubectl get pv,pvc -n sre-lab
   kubectl get pods -n sre-lab -l app=postgres-db
   ```
2. Write a verification marker into the persistent volume, delete the Pod, wait for replacement, and verify the marker survives:
   ```bash
   kubectl exec -n sre-lab deploy/postgres-db -- sh -c 'echo "persisted-sre-record" > /var/lib/postgresql/data/sre_check.txt'
   kubectl delete pod -n sre-lab -l app=postgres-db
   kubectl rollout status deployment/postgres-db -n sre-lab --timeout=60s
   kubectl exec -n sre-lab deploy/postgres-db -- cat /var/lib/postgresql/data/sre_check.txt
   ```
3. Run automated verification:
   ```bash
   ./scripts/troubleshooting/sre-lab-runner.sh verify 09
   ```
