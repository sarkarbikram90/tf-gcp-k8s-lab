# Lab 05: Workload Startup Failures (`CrashLoopBackOff` & `ImagePullBackOff`)

## Objective
Diagnose and remediate multi-replica application pods failing to start due to:
1. **`ImagePullBackOff` / `ErrImagePull`**: Invalid container image tag or unreachable registry.
2. **`CrashLoopBackOff`**: Missing `ConfigMap`/`Secret` environment references, invalid container entrypoint command, or misconfigured `livenessProbe` killing the container before initialization completes.

---

## First-Principles Mental Model
When a Pod is scheduled onto a node, `kube-scheduler` has finished its job and handed execution to the node's **`kubelet`**:
1. `kubelet` invokes **`containerd`** via the CRI (Container Runtime Interface) `ImageService` to pull the image. If image resolution, tag lookup, or registry authentication fails, `kubelet` emits `ErrImagePull` and backs off exponentially (`ImagePullBackOff`).
2. Once the image is pulled, `containerd` creates the OCI container namespace and executes the process (`ENTRYPOINT` / `command`). If PID 1 exits non-zero—or if `kubelet` kills the container because a `livenessProbe` fails—`kubelet` restarts the container with an exponential delay (`10s`, `20s`, `40s`, up to `5m`), reporting `CrashLoopBackOff`.

> **SRE Rule:** Never start by deleting a `CrashLoopBackOff` Pod. The ReplicaSet controller will simply create a new Pod with the exact same broken specification. Always inspect **Events**, **current/previous container logs**, and the **Pod spec** first.

---

## Automated Failure Injection

Inject this lab scenario using the SRE lab runner:

```bash
./scripts/troubleshooting/sre-lab-runner.sh inject 05
```

---

## Failure Symptoms
1. Running `kubectl get pods -n sre-lab` shows:
   - `payment-worker-*` stuck in `ImagePullBackOff` or `ErrImagePull`
   - `checkout-api-*` stuck in `CrashLoopBackOff` (or `CreateContainerConfigError`) with increasing `RESTARTS`

---

## Diagnosis Workflow

### Step 1: Triage Workload Status & Events
```bash
kubectl get pods -n sre-lab -o wide
kubectl get events -n sre-lab --sort-by=.metadata.creationTimestamp
```

### Step 2: Diagnose `ImagePullBackOff` (`payment-worker`)
Inspect the Pod description and look at the `Events` section at the bottom:
```bash
kubectl describe pod -n sre-lab -l app=payment-worker
```
Look for messages such as:
```text
Warning  Failed  ...  Failed to pull image "registry.k8s.io/pause:99.99-nonexistent": rpc error: code = NotFound
```
On the worker node itself, you can also verify runtime image pull behavior directly via `crictl`:
```bash
sudo crictl images
sudo journalctl -u containerd -e --no-pager | tail -n 30
```

### Step 3: Diagnose `CrashLoopBackOff` (`checkout-api`)
1. Check both current and **previous** (terminated) container logs:
   ```bash
   kubectl logs -n sre-lab -l app=checkout-api
   kubectl logs -n sre-lab -l app=checkout-api --previous
   ```
2. Check the last termination state (`Exit Code` and `Reason`) and probe configuration:
   ```bash
   kubectl describe pod -n sre-lab -l app=checkout-api
   ```
   - **Exit Code `1` / `127` / `128`**: Application error, invalid flag, or bad `command` / `args`.
   - **`CreateContainerConfigError`**: Referenced `ConfigMap` or `Secret` key does not exist.
   - **`Killing: Container ... failed liveness probe`**: Probe path, port, or `initialDelaySeconds` is misconfigured.
3. Inspect the Deployment specification:
   ```bash
   kubectl get deploy checkout-api -n sre-lab -o yaml
   kubectl get configmap,secret -n sre-lab
   ```

---

## Remediation

### 1. Fix `payment-worker` Image Tag
Update the Deployment to use a valid image tag (`registry.k8s.io/pause:3.9` or `nginx:1.27-alpine`):
```bash
kubectl set image deployment/payment-worker -n sre-lab worker=nginx:1.27-alpine
```

### 2. Fix `checkout-api` Configuration, Command & Liveness Probe
1. Create or patch the missing `ConfigMap` key required by the workload:
   ```bash
   kubectl create configmap checkout-config -n sre-lab \
     --from-literal=APP_MODE=production \
     --dry-run=client -o yaml | kubectl apply -f -
   ```
2. Patch the Deployment to fix the broken startup command and point the `livenessProbe` to the valid HTTP port (`80`):
   ```bash
   kubectl patch deployment checkout-api -n sre-lab --type='json' -p='[
     {"op": "remove", "path": "/spec/template/spec/containers/0/command"},
     {"op": "replace", "path": "/spec/template/spec/containers/0/livenessProbe/httpGet/port", "value": 80}
   ]'
   ```

### 3. Verify Recovery
```bash
./scripts/troubleshooting/sre-lab-runner.sh verify 05
```
All pods in `sre-lab` for `payment-worker` and `checkout-api` should reach `1/1 Running` with `0` new restarts.
