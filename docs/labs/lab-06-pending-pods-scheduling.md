# Lab 06: Scheduling & Placement Failures (`Pending` Pods, Taints & Affinity)

## Objective
Diagnose and resolve Pods stuck in the `Pending` phase by systematically analyzing **`kube-scheduler`** filter predicates: CPU/memory capacity constraints, node `Taints` & `Tolerations`, and `nodeSelector` / `nodeAffinity` rules.

---

## First-Principles Mental Model
When a Pod remains in `Pending`, **no `kubelet` has taken ownership of it yet** (`spec.nodeName` is empty).
Ask the five Staff Engineer questions:
1. **Which component is responsible?** `kube-scheduler`.
2. **What constraints does it evaluate?**
   - **Filtering (Predicates):** Which nodes have sufficient `Allocatable` CPU/memory (`requests`), matching labels (`nodeSelector` / `nodeAffinity`), untainted status (or matching `tolerations`), and available volume topology?
   - **Scoring (Priorities):** Ranks the feasible nodes.
3. **Does the cluster have sufficient resources?** Compare `kubectl describe nodes` (`Allocated resources`) against the Pod's `resources.requests`.
4. **Are taints, tolerations, or affinity rules preventing placement?** Inspect `node.spec.taints` and `pod.spec.affinity`.
5. **What evidence confirms the root cause?** The `FailedScheduling` event emitted by `default-scheduler`.

---

## Automated Failure Injection

```bash
./scripts/troubleshooting/sre-lab-runner.sh inject 06
```

---

## Failure Symptoms
Running `kubectl get pods -n sre-lab` shows two Deployments with Pods stuck in `Pending`:
- `batch-scorer-*` (`0/2` Ready, `Pending`)
- `gpu-inference-sim-*` (`0/1` Ready, `Pending`)

---

## Diagnosis Workflow

### Step 1: Filter All `Pending` Pods & Inspect `FailedScheduling` Events
```bash
kubectl get pods -n sre-lab --field-selector=status.phase=Pending
kubectl describe pod -n sre-lab -l app=batch-scorer
kubectl describe pod -n sre-lab -l app=gpu-inference-sim
```
Look closely at the `Events` table:
```text
Warning  FailedScheduling  default-scheduler  0/3 nodes are available: 1 node(s) had untolerated taint {node-role.kubernetes.io/control-plane: }, 2 Insufficient cpu.
```
or:
```text
Warning  FailedScheduling  default-scheduler  0/3 nodes are available: 3 node(s) didn't match Pod's node affinity/selector.
```

### Step 2: Audit Node Allocatable Capacity vs. Requests
Check how much CPU and memory each worker node actually has available:
```bash
kubectl describe nodes | grep -E "Name:|Taints:|Allocatable:|cpu:|memory:" -A 2
```
Inspect the `batch-scorer` CPU/memory requests:
```bash
kubectl get deploy batch-scorer -n sre-lab -o jsonpath='{.spec.template.spec.containers[0].resources}'
```

### Step 3: Audit Node Labels & Taints
```bash
kubectl get nodes --show-labels
kubectl get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints
```
Inspect what `gpu-inference-sim` requires:
```bash
kubectl get deploy gpu-inference-sim -n sre-lab -o jsonpath='{.spec.template.spec.nodeSelector}'
```

---

## Remediation

### 1. Right-Size `batch-scorer` Resource Requests
Reduce the unrealistic CPU request (e.g., `64` cores) to a realistic reservation (`100m` CPU, `128Mi` memory) so `kube-scheduler` can fit the replicas onto worker nodes:
```bash
kubectl set resources deployment/batch-scorer -n sre-lab \
  --requests=cpu=100m,memory=128Mi \
  --limits=cpu=250m,memory=256Mi
```

### 2. Satisfy `gpu-inference-sim` Placement Constraints
Either label a worker node to represent the target accelerator pool (and add the matching toleration if tainted) or update the workload's `nodeSelector`:
```bash
# Option A: Label a worker node to satisfy the workload's nodeSelector
WORKER_NODE=$(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[0].metadata.name}')
kubectl label node "${WORKER_NODE}" accelerator=inference-sim --overwrite
```

### 3. Verify Recovery
```bash
./scripts/troubleshooting/sre-lab-runner.sh verify 06
```
Both `batch-scorer` and `gpu-inference-sim` Pods should transition from `Pending` to `Running`.
