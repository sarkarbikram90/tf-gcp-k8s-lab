# Lab 07: Memory Exhaustion & `OOMKilled` (Exit Code 137 & QoS Classes)

## Objective
Diagnose a container repeatedly terminated by the Linux kernel Out-Of-Memory (OOM) killer (`OOMKilled`, Exit Code `137`), trace the event in both Kubernetes pod status and Linux kernel cgroup logs, and right-size container memory `requests`/`limits` to establish `Guaranteed` or properly bounded `Burstable` Quality of Service (QoS).

---

## First-Principles Mental Model
Kubernetes does not enforce memory limits itself—the **Linux kernel cgroups (`memory.max` in cgroup v2)** enforce them:
1. When you set `resources.limits.memory: 32Mi` on a container, `kubelet` instructs `containerd`/`runc` to configure the container's cgroup memory ceiling at `32Mi`.
2. When the process inside the container allocates anonymous memory (heap/stack) exceeding `memory.max`, the Linux kernel's **OOM Killer** immediately sends `SIGKILL` (`9`) to the process.
3. In Unix exit code conventions, a process killed by signal $N$ exits with code $128 + N = 128 + 9 = 137$.
4. `containerd` reports the exit status (`137`) and cgroup OOM event to `kubelet`, which surfaces `Reason: OOMKilled` in `lastState.terminated`.

---

## Automated Failure Injection

```bash
./scripts/troubleshooting/sre-lab-runner.sh inject 07
```

---

## Failure Symptoms
1. `kubectl get pods -n sre-lab` shows `memory-hog-service-*` in `OOMKilled` or `CrashLoopBackOff`.
2. Container restarts increment every time the workload attempts to allocate its working memory buffer.

---

## Diagnosis Workflow

### Step 1: Inspect Pod Termination State & Exit Code
```bash
kubectl get pod -n sre-lab -l app=memory-hog-service -o yaml | grep -A 12 lastState
kubectl describe pod -n sre-lab -l app=memory-hog-service
```
Look for:
```text
    Last State:     Terminated
      Reason:       OOMKilled
      Exit Code:    137
```
Check the Pod's assigned **QoS Class** (`Guaranteed`, `Burstable`, or `BestEffort`):
```bash
kubectl get pod -n sre-lab -l app=memory-hog-service -o jsonpath='{.items[0].status.qosClass}{"\n"}'
```

### Step 2: Inspect Live Resource Consumption (if Metrics Server is active)
```bash
kubectl top pods -n sre-lab
```

### Step 3: Verify Below Kubernetes (Linux Kernel OOM Logs)
SSH onto the worker node where the Pod ran and inspect the kernel ring buffer (`dmesg` / `journalctl -k`):
```bash
sudo dmesg -T | grep -i -E 'oom|killed process|memory' | tail -n 20
# Or via systemd journal:
sudo journalctl -k -e --no-pager | grep -i oom
```
You will see the exact kernel cgroup trace:
```text
Memory cgroup out of memory: Killed process ...anon-rss:...kB
```

---

## Remediation

### 1. Right-Size Memory Limits & Align Requests (`Guaranteed` QoS)
Inspect what the application actually allocates (`kubectl get deploy memory-hog-service -n sre-lab -o yaml`). The workload allocates a ~40MB buffer inside a container limited to `16Mi`.

Update the Deployment's memory `requests` and `limits` to `128Mi` (and matching CPU `requests`/`limits` of `100m` to promote the Pod to the `Guaranteed` QoS class):
```bash
kubectl set resources deployment/memory-hog-service -n sre-lab \
  --requests=cpu=100m,memory=128Mi \
  --limits=cpu=100m,memory=128Mi
```

### 2. Verify Recovery & QoS Promotion
```bash
./scripts/troubleshooting/sre-lab-runner.sh verify 07
```
Confirm the Pod is `Running`, `RESTARTS` stays `0`, and `qosClass` is now `Guaranteed`.
