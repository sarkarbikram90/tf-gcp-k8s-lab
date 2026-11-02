# Day 1 Walkthrough (Nov 2): Linux, Containers & Kubernetes Architecture

> **Time Allocation (180 mins):**
> - **Conceptual Understanding (`35 min`)**: Linux isolation primitives (`namespaces`, `cgroups`), OCI runtime (`containerd` + `runc`), and Control Plane vs. Worker responsibilities.
> - **Hands-On Engineering (`100 min`)**: Inspect live processes, container sandboxes, static Pod manifests, and CRI communication on your `tf-gcp-k8s-lab` cluster.
> - **Troubleshooting (`25 min`)**: Trace what happens when `kubelet` or CNI is disrupted ([Lab 01](../labs/lab-01-broken-cni.md) / [Lab 03](../labs/lab-03-kubelet-cert-expiry.md)).
> - **Engineering Journal (`20 min`)**: Answer the Day 1 verification test in your journal ([`journal-template.md`](journal-template.md)).

---

## Part 1: Conceptual Understanding (35 Minutes)

### 1. The Five-Questions Check
Before touching the terminal, make sure you can answer:
1. **What problem do Linux containers solve?** Process isolation without full hardware virtualization overhead. A "container" is not a real kernel object—it is a normal Linux process constrained by:
   - **Namespaces** (*what the process can see*): `pid`, `net`, `mnt`, `ipc`, `uts`, `user`, `cgroup`.
   - **Control Groups (`cgroups` v2)** (*how much the process can use*): CPU shares/quotas (`cpu.max`), memory limits (`memory.max`), I/O weight.
   - **`seccomp` / Capabilities / AppArmor** (*what syscalls the process is allowed to invoke*).
2. **How do `kubelet`, `containerd`, and `runc` divide responsibility?**
   - `kubelet` watches the `kube-apiserver` for Pods bound to its `nodeName`.
   - `kubelet` speaks gRPC over a Unix socket (`/run/containerd/containerd.sock`) using the **CRI (Container Runtime Interface)** to `containerd`.
   - `containerd` pulls the OCI image, creates the Pod network sandbox (calling the **CNI plugin** binary in `/opt/cni/bin/`), and invokes the low-level OCI runtime **`runc`** to fork the container process inside its Linux namespaces and cgroups.

---

## Part 2: Hands-On Engineering Lab (100 Minutes)

### Step 1: Inspect Cluster Nodes & Control Plane Topology
From your control plane node (via IAP tunnel `gcloud compute ssh k8s-lab-control-plane --tunnel-through-iap`):

```bash
kubectl get nodes -o wide
kubectl get pods -n kube-system -o wide
```

Notice which pods in `kube-system` have the node name appended to their Pod name (e.g., `kube-apiserver-k8s-lab-control-plane`, `etcd-k8s-lab-control-plane`, `kube-controller-manager-...`, `kube-scheduler-...`):
- Those are **Static Pods** managed directly by the local `kubelet` reading `/etc/kubernetes/manifests/`, NOT scheduled by `kube-scheduler`!
- `coredns-*` and `kube-flannel-ds-*` are regular API-server-managed `Deployment` and `DaemonSet` Pods.

### Step 2: Inspect Static Pod Manifests & Kubelet Configuration
```bash
ls -la /etc/kubernetes/manifests/
sudo head -n 45 /etc/kubernetes/manifests/kube-apiserver.yaml
systemctl status kubelet --no-pager
cat /var/lib/kubelet/config.yaml | grep -E "staticPodPath|cgroupDriver|clusterDNS"
```
Confirm that `staticPodPath: /etc/kubernetes/manifests` and `cgroupDriver: systemd` match what `01-install-prereqs.sh` configured in `/etc/containerd/config.toml`.

### Step 3: Trace `kubelet` → `containerd` → `runc` → Linux Namespaces & Cgroups
1. List running Pod sandboxes and containers directly via CRI (`crictl`):
   ```bash
   sudo crictl pods
   sudo crictl ps
   ```
2. Pick a running container ID from `sudo crictl ps` and inspect its host Linux PID, namespaces, and cgroup limits:
   ```bash
   CID=$(sudo crictl ps -q | head -n 1)
   PID=$(sudo crictl inspect --output go-template --template '{{.info.pid}}' "${CID}")
   echo "Container ID: ${CID} -> Host Linux PID: ${PID}"

   # Inspect the Linux namespaces attached to this process:
   sudo lsns -p "${PID}"

   # Inspect its cgroup v2 hierarchy and memory/CPU controllers:
   cat "/proc/${PID}/cgroup"
   ```
3. See the container process in the host process tree alongside `containerd-shim-runc-v2`:
   ```bash
   ps -ef | grep -E "containerd-shim|${PID}"
   ```
   > **Key Insight:** Notice that `containerd-shim-runc-v2` is the parent of the container process—`runc` exits immediately after creating the container namespace so that upgrading `containerd` does not kill running containers!

---

## Part 3: Troubleshooting Exercise (25 Minutes)

Run **Lab 01** or **Lab 03** using the automated lab runner:
```bash
./scripts/troubleshooting/sre-lab-runner.sh inject 01
./scripts/troubleshooting/sre-lab-runner.sh verify 01
```
Also test what happens when you trace a `kubectl create deployment` call at API verbosity level 8:
```bash
kubectl create deployment day1-nginx --image=nginx:1.27-alpine --dry-run=client -o yaml
kubectl get pods -v=6
```

---

## Part 4: End-of-Day Test (20 Minutes — Engineering Journal)

Without looking at notes, write out in your journal the complete 8-stage sequence that occurs when you run:
```bash
kubectl create deployment nginx --image=nginx:1.27-alpine
```
Check your explanation against these 8 stages:
1. `kubectl` sends an authenticated `POST /apis/apps/v1/namespaces/default/deployments` HTTPS request to `kube-apiserver`.
2. `kube-apiserver` authenticates, authorizes (RBAC), runs Admission Controllers (mutating + validating), and persists the `Deployment` object in **`etcd`**.
3. **`deployment-controller`** (inside `kube-controller-manager`), watching `Deployment` objects via a list-watch informer, sees the new `Deployment` with no active `ReplicaSet` and creates a `ReplicaSet` object via `kube-apiserver` → `etcd`.
4. **`replicaset-controller`** sees `0/1` existing Pods for that `ReplicaSet` and creates a `Pod` object (with `spec.nodeName: ""`, `status.phase: Pending`) via `kube-apiserver` → `etcd`.
5. **`kube-scheduler`** watches unbound Pods (`nodeName == ""`), runs **Filtering** (CPU/memory requests, taints, nodeSelector/affinity) and **Scoring**, and writes a `Binding` subresource setting `spec.nodeName = <chosen-worker>` in `etcd`.
6. **`kubelet`** on `<chosen-worker>` watches Pods bound to its node name, sees the newly bound Pod, and calls **`containerd`** over CRI (`RunPodSandbox` + `CreateContainer` + `StartContainer`).
7. **`containerd`** invokes the **CNI plugin** (`/opt/cni/bin/flannel`) to create the `veth` pair and assign a Pod IP in the container's network namespace, pulls `nginx:1.27-alpine` if not cached, and calls **`runc`** to start the container inside its Linux namespaces and `systemd` cgroup.
8. **`kubelet`** executes any configured `startupProbe`/`readinessProbe`/`livenessProbe` and patches the Pod's `status` (`Phase: Running`, `Ready: True`, `podIP`) back to `kube-apiserver` → `etcd`.
