# Week 1 Walkthrough Guide (Days 3–7): Workloads, Scheduling, Networking & Lifecycle

This guide provides the structured 180-minute hands-on labs, commands, and verification answers for **Days 3 through 7** of the [14-Day Kubernetes Engineering Sprint](README.md).

---

## Day 3 (Nov 4): Pods, ReplicaSets & Deployments

### 1. Conceptual Check (35 min)
- **Multi-container Pod patterns**:
  - **Init Containers** run sequentially to completion *before* any app container starts (e.g., waiting for database schema migration or pre-populating a volume).
  - **Sidecar Containers** run alongside the primary container sharing the same network namespace (`localhost`) and volume mounts (e.g., log shippers, Envoy proxies).
- **RollingUpdate parameters**: `maxSurge` (how many extra Pods can be created above desired count during rollout) and `maxUnavailable` (how many Pods can be unavailable during rollout).

### 2. Hands-On Lab (100 min)
```bash
# 1. Create a Deployment and scale 1 -> 5 replicas
kubectl create deployment web-app --image=nginx:1.26-alpine --replicas=1
kubectl scale deployment web-app --replicas=5
kubectl get pods -l app=web-app -o wide

# 2. Perform a recorded rolling update and watch two ReplicaSets trade replicas
kubectl set image deployment/web-app nginx=nginx:1.27-alpine
kubectl rollout status deployment/web-app
kubectl get rs -l app=web-app

# 3. Roll back to the previous revision
kubectl rollout history deployment/web-app
kubectl rollout undo deployment/web-app
kubectl get rs -l app=web-app
kubectl delete deployment web-app
```

### 3. Troubleshooting Lab (25 min)
Execute **[Lab 05 (`CrashLoopBackOff` & `ImagePullBackOff`)](../labs/lab-05-crashloop-and-imagepull.md)**:
```bash
./scripts/troubleshooting/sre-lab-runner.sh inject 05
./scripts/troubleshooting/sre-lab-runner.sh verify 05
```

### 4. End-of-Day Verification Answer (20 min)
- **Question:** *What happens internally when you scale a Deployment from 2 to 5 replicas?*
- **Answer:** `kubectl scale` sends a `PATCH` updating `spec.replicas: 5` on the `Deployment` in `etcd`. `deployment-controller` observes the change and updates `spec.replicas: 5` on the active `ReplicaSet`. `replicaset-controller` sees 2 existing Pods vs. 5 desired, creates 3 new unbound `Pod` objects in `etcd`, `kube-scheduler` binds each to a worker node, and each node's `kubelet` instructs `containerd` to start the containers.

---

## Day 4 (Nov 5): Scheduling & Resource Management

### 1. Conceptual Check (35 min)
- **Requests vs. Limits**:
  - **`requests`** are used by `kube-scheduler` during the **Filter/Score** phase to reserve capacity on a node (and configure Linux cgroup `cpu.weight`).
  - **`limits`** are enforced at runtime by the Linux kernel: CPU limits throttle processes via CFS quota (`cpu.max`), whereas exceeding memory limits triggers the kernel **OOMKiller** (`SIGKILL` / exit code `137` / `OOMKilled`).
- **QoS Classes**: `Guaranteed` (`requests == limits` for all containers), `Burstable` (at least one request/limit set, not equal), `BestEffort` (no requests or limits set; first to be evicted under node memory pressure).

### 2. Hands-On Lab (100 min)
```bash
# 1. Taint worker-01 and observe how normal Pods avoid it
WORKER1=$(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[0].metadata.name}')
kubectl taint nodes "${WORKER1}" dedicated=gpu-workloads:NoSchedule

# 2. Schedule a Pod that tolerates the taint
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: gpu-tolerant-pod
spec:
  tolerations:
    - key: "dedicated"
      operator: "Equal"
      value: "gpu-workloads"
      effect: "NoSchedule"
  containers:
    - name: app
      image: nginx:1.27-alpine
      resources:
        requests:
          cpu: "100m"
          memory: "128Mi"
        limits:
          cpu: "100m"
          memory: "128Mi"
EOF

kubectl get pod gpu-tolerant-pod -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName,QOS:.status.qosClass

# 3. Clean up taint and test pod
kubectl delete pod gpu-tolerant-pod
kubectl taint nodes "${WORKER1}" dedicated=gpu-workloads:NoSchedule-
```

### 3. Troubleshooting Lab (25 min)
Execute **[Lab 06 (`Pending` Pods)](../labs/lab-06-pending-pods-scheduling.md)** and **[Lab 07 (`OOMKilled`)](../labs/lab-07-oomkilled-memory-limits.md)**:
```bash
./scripts/troubleshooting/sre-lab-runner.sh inject 06
./scripts/troubleshooting/sre-lab-runner.sh verify 06
./scripts/troubleshooting/sre-lab-runner.sh inject 07
./scripts/troubleshooting/sre-lab-runner.sh verify 07
```

### 4. End-of-Day Verification Answer (20 min)
- **Question:** *Why can a Pod remain `Pending` even when every worker node reports `Ready`?*
- **Answer:** A `Ready` node can still fail `kube-scheduler` Filtering due to: (1) insufficient allocatable CPU/memory/ephemeral-storage to satisfy the Pod's `requests`, (2) untolerated node taints (`NoSchedule` / `NoExecute`), (3) unmatched `nodeSelector` or `nodeAffinity`, (4) unsatisfied `podAntiAffinity` / `topologySpreadConstraints`, or (5) an unbound `PersistentVolumeClaim` (`PVC Pending`).

---

## Day 5 (Nov 6): Kubernetes Networking Fundamentals

### 1. Conceptual Check (35 min)
Review Week 2 & Week 3 of the **[30-Day Networking Deep-Dive Roadmap](../networking/30-day-networking-roadmap.md)**.

### 2. Hands-On Lab (100 min)
Deploy the networking diagnostic suite and trace packet routing:
```bash
kubectl apply -f kubernetes/networking/01-netshoot-debug-ds.yaml
kubectl apply -f kubernetes/networking/02-gateway-and-ingress-lab.yaml
./scripts/networking/trace-packet-path.sh
```

### 3. Troubleshooting Lab (25 min)
Execute **[Lab 01 (Broken CNI)](../labs/lab-01-broken-cni.md)**:
```bash
./scripts/troubleshooting/sre-lab-runner.sh inject 01
./scripts/troubleshooting/sre-lab-runner.sh verify 01
```

### 4. End-of-Day Verification Answer (20 min)
- **Question:** *How does a request reach a Pod when the client only knows the Kubernetes Service name?*
- **Answer:** (1) The client queries `CoreDNS` (`10.96.0.10:53`) using search domains in `/etc/resolv.conf` to resolve `<svc>.<ns>.svc.cluster.local` to the Service `ClusterIP` VIP; (2) the client sends a packet to `ClusterIP:Port`; (3) the local node's kernel netfilter hits `kube-proxy`'s `KUBE-SERVICES` → `KUBE-SVC-*` → `KUBE-SEP-*` rules (populated from `EndpointSlices`), which DNATs the destination IP to a healthy backing `PodIP:TargetPort`; (4) if the target Pod is on another node, the CNI (`flannel.1`) encapsulates and routes the packet across the GCP VPC to the target worker node's `cni0` bridge and `veth` pair.

---

## Day 6 (Nov 7): Ingress, Gateway API & NetworkPolicies

### 1. Conceptual Check (35 min)
- **North-South vs. East-West**:
  - **North-South** traffic enters/leaves the cluster (`Client → LoadBalancer → Ingress / Gateway Controller → Service → Pod`).
  - **East-West** traffic moves Pod-to-Pod inside the cluster and is governed by zero-trust **`NetworkPolicy`** rules.

### 2. Hands-On Lab (100 min)
Apply the zero-trust default-deny and DNS egress policies from `kubernetes/security/network-policies/` into a test namespace and verify isolation:
```bash
kubectl apply -f kubernetes/networking/02-gateway-and-ingress-lab.yaml
kubectl get ingress,networkpolicy -n net-lab -o wide
```

### 3. Troubleshooting Lab (25 min)
Execute **[Lab 08 (Service Selector Mismatch & NetworkPolicy Blackhole)](../labs/lab-08-service-networking-and-dns.md)**:
```bash
./scripts/troubleshooting/sre-lab-runner.sh inject 08
./scripts/troubleshooting/sre-lab-runner.sh verify 08
```

### 4. End-of-Day Verification Answer (20 min)
- **Question:** *Why does creating an `Ingress` resource alone not necessarily expose your application?*
- **Answer:** An `Ingress` object is only a declarative routing configuration stored in `etcd`. Without a running **Ingress Controller** (e.g., `ingress-nginx`, `traefik`, or a Gateway API controller) watching `Ingress` resources and configuring a reverse-proxy data plane, nothing is listening for or forwarding the HTTP/HTTPS traffic.

---

## Day 7 (Nov 8): Configuration & Application Lifecycle

### 1. Conceptual Check (35 min)
- **Three Probe Types**:
  - **`startupProbe`**: Runs first; disables `livenessProbe` and `readinessProbe` until it succeeds so slow-starting workloads (like `vLLM` loading multi-GB model weights) are not prematurely killed.
  - **`readinessProbe`**: Controls whether the Pod's IP is marked `ready: true` in `EndpointSlices`. If it fails, the Pod is **not killed**, but `kube-proxy` and Ingress stop sending it traffic.
  - **`livenessProbe`**: Detects deadlocks. If it fails repeatedly (`failureThreshold`), `kubelet` restarts the container.
- **Volume-mounted ConfigMaps vs. Env Vars**: Mounted `ConfigMap` files auto-update via kubelet sync loops (unless `subPath` is used), whereas `env` variables are static for the lifetime of the container process.

### 2. Hands-On Lab (100 min)
Inspect how probes and ConfigMaps are wired in the **Level 5 AI Inference Platform** ([`02-vllm-serving-deployment.yaml`](../../kubernetes/ai-inference/02-vllm-serving-deployment.yaml)) and **`Barnacles` Platform** ([`03-server-statefulset.yaml`](../../kubernetes/platform-barnacles/03-server-statefulset.yaml)).

### 3. Troubleshooting Lab (25 min)
Execute **[Lab 10 (Stuck Rollouts & Failing Readiness Probes)](../labs/lab-10-stuck-rollout-and-probes.md)**:
```bash
./scripts/troubleshooting/sre-lab-runner.sh inject 10
./scripts/troubleshooting/sre-lab-runner.sh verify 10
```

### 4. End-of-Week Verification Answer (20 min)
- **Question:** *Explain how Kubernetes decides whether an application should receive traffic, be restarted, or be left alone during startup.*
- **Answer:** While `startupProbe` is still running within its `failureThreshold * periodSeconds` window, Kubernetes leaves the container alone to finish initializing. Once `startupProbe` succeeds, `readinessProbe` determines whether the Pod's endpoint is marked `ready: true` in `EndpointSlices` (receiving Service traffic), while `livenessProbe` determines whether `kubelet` must kill and restart the container due to an unrecoverable deadlock.
