# Kubernetes SRE Troubleshooting Laboratory (`docs/labs`)

> **Engineering Objective:** Don't aim to memorize `kubectl` commands. Aim to walk into an unfamiliar, malfunctioning Kubernetes cluster, form a first-principles hypothesis, inspect the control-plane/node/Linux layers, isolate the root cause with evidence, restore service, and write a post-mortem that prevents recurrence.

---

## 1. The First-Principles SRE Diagnostic Framework

Never start an investigation by deleting a failing Pod. Before running a single remediation command, answer these **five Staff Engineer questions**:

| # | Diagnostic Question | Example: `Pending` Pod | Example: `Service` Unreachable |
| :--- | :--- | :--- | :--- |
| **1** | **Which component is responsible?** | `kube-scheduler` | `CoreDNS` → `kube-proxy` (`iptables`/`IPVS`) → CNI / `NetworkPolicy` |
| **2** | **What state/constraints does it evaluate?** | Node `Allocatable` CPU/Mem, `Taints`, `nodeSelector`, `Affinity`, PVC binding | Service `selector` → `EndpointSlices` → `targetPort` → Pod socket |
| **3** | **Where does the state diverge?** | Desired (`spec.replicas`) vs. Scheduled (`spec.nodeName == ""`) | Service exists, but `Endpoints` is empty or packets drop in `iptables` |
| **4** | **What evidence confirms the hypothesis?** | `FailedScheduling` Event & `kubectl describe node` resource table | `kubectl get endpointslices`, `ss -tulpn`, `iptables-save`, `nslookup` |
| **5** | **How do I fix root cause & prove recovery?** | Right-size requests or satisfy affinity; verify `1/1 Running` | Align selector/`targetPort`/`NetworkPolicy`; verify HTTP `200 OK` |

---

## 2. The 14-Scenario SRE Troubleshooting Matrix (Core Kubernetes + Barnacles + vLLM + IDP)

Use the automated lab runner ([`scripts/troubleshooting/sre-lab-runner.sh`](../../scripts/troubleshooting/sre-lab-runner.sh)) to inject, verify, or run blind timed drills (`random`) across the scenarios below:

| Lab | Scenario | Layer / Component | Domain | Inject Command | Runbook |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **01** | **Broken CNI & CoreDNS Stuck** | Node / CNI (`/etc/cni/net.d`, Flannel) | Troubleshooting (30%) & Networking (20%) | `./scripts/troubleshooting/sre-lab-runner.sh inject 01` | [Lab 01](lab-01-broken-cni.md) |
| **02** | **Control Plane & `etcd` Quorum Loss** | Control Plane (`etcd`, Static Pods) | Cluster Architecture (25%) & Troubleshooting (30%) | `./scripts/troubleshooting/sre-lab-runner.sh inject 02` | [Lab 02](lab-02-etcd-quorum-loss.md) |
| **03** | **Node `NotReady`, Kubelet & PKI Expiry** | Node (`kubelet`, `containerd`, X.509 PKI) | Cluster Architecture (25%) & Troubleshooting (30%) | `./scripts/troubleshooting/sre-lab-runner.sh inject 03` | [Lab 03](lab-03-kubelet-cert-expiry.md) |
| **04** | **Node `DiskPressure` & Storage Eviction** | Node Linux FS (`/var/lib/containerd`, logs) | Troubleshooting (30%) & Storage (10%) | `./scripts/troubleshooting/sre-lab-runner.sh inject 04` | [Lab 04](lab-04-node-pressure-disk-full.md) |
| **05** | **`CrashLoopBackOff` & `ImagePullBackOff`** | Kubelet / CRI / Container Startup & Probes | Workloads (15%) & Troubleshooting (30%) | `./scripts/troubleshooting/sre-lab-runner.sh inject 05` | [Lab 05](lab-05-crashloop-and-imagepull.md) |
| **06** | **`Pending` Pods, Resource Starvation & Affinity** | `kube-scheduler` Predicates, Taints, Requests | Workloads & Scheduling (15%) | `./scripts/troubleshooting/sre-lab-runner.sh inject 06` | [Lab 06](lab-06-pending-pods-scheduling.md) |
| **07** | **`OOMKilled` (Exit 137) & Memory QoS** | Linux Kernel cgroup OOM Killer & Limits | Workloads (15%) & Troubleshooting (30%) | `./scripts/troubleshooting/sre-lab-runner.sh inject 07` | [Lab 07](lab-07-oomkilled-memory-limits.md) |
| **08** | **Service Blackhole, DNS & `NetworkPolicy`** | `CoreDNS`, `EndpointSlices`, `kube-proxy`, CNI | Services & Networking (20%) | `./scripts/troubleshooting/sre-lab-runner.sh inject 08` | [Lab 08](lab-08-service-networking-and-dns.md) |
| **09** | **`PVC Pending`, `StorageClass` & Persistence** | `pv-controller`, CSI, Static/Dynamic Binding | Storage (10%) | `./scripts/troubleshooting/sre-lab-runner.sh inject 09` | [Lab 09](lab-09-pvc-pending-storage.md) |
| **10** | **Stuck Rollout, Readiness Probes & `PDB`** | `deployment-controller`, Probes, Eviction API | Workloads (15%) & Troubleshooting (30%) | `./scripts/troubleshooting/sre-lab-runner.sh inject 10` | [Lab 10](lab-10-stuck-rollout-and-probes.md) |
| **11** | **`Barnacles` Partition & Edge Spool Drain** | Project 2 (`Barnacles` Agent FIFO Spool & NetPol) | Distributed Logging & Network Partition | `./scripts/troubleshooting/sre-lab-runner.sh inject 11` | [Lab 11](lab-11-barnacles-spool-partition.md) |
| **12** | **`vLLM` Queue Saturation & Readiness Shedding** | Level 5 (`vLLM` Continuous Batching & Probes) | AI Inference SRE & Token Economics | `./scripts/troubleshooting/sre-lab-runner.sh inject 12` | [Lab 12](lab-12-vllm-queue-saturation.md) |
| **13** | **IDP Governance & Kyverno Hygiene Violations** | Level 6 (Kyverno Policies & Restricted PSS) | Platform Engineering & Policy-as-Code | `./scripts/troubleshooting/sre-lab-runner.sh inject 13` | [Lab 13](lab-13-idp-kyverno-admission.md) |
| **14** | **`ExternalSecret` & Secret Key Mapping Drift** | Level 6 (External Secrets Operator & GCP SM) | Zero-Trust Cloud Secrets & Config | `./scripts/troubleshooting/sre-lab-runner.sh inject 14` | [Lab 14](lab-14-external-secret-sync.md) |

---

## 3. Running Blind On-Call Drills (`20–30 Minute Timed Mode`)

To build genuine troubleshooting intuition without knowing the root cause in advance, run a **random failure simulation**:

```bash
# Inject a mystery workload/network/storage/scheduling failure into namespace 'sre-lab'
./scripts/troubleshooting/sre-lab-runner.sh random

# Check current status of the lab environment
./scripts/troubleshooting/sre-lab-runner.sh status

# Verify your fix once you have resolved the incident
./scripts/troubleshooting/sre-lab-runner.sh verify current

# Clean up all fault-injection resources
./scripts/troubleshooting/sre-lab-runner.sh reset all
```

After every drill, document your findings using the **[SRE Incident Report Template](incident-report-template.md)**.

---

## 4. The Complete SRE Troubleshooting Command Toolkit

### Layer 1: Kubernetes Control Plane & Workload Investigation (`kubectl`)

```bash
# 1. Cluster & Node Health
kubectl get nodes -o wide
kubectl describe node <node-name> | grep -A 8 Conditions
kubectl cluster-info
kubectl get events -A --sort-by=.metadata.creationTimestamp

# 2. Workload & Container Lifecycle
kubectl get pods -A -o wide
kubectl get pods -A --field-selector=status.phase!=Running
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace> --all-containers
kubectl logs <pod-name> -n <namespace> --previous

# 3. Scheduling & Resource Capacity
kubectl get pods -A --field-selector=status.phase=Pending
kubectl get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints
kubectl top nodes
kubectl top pods -A --sort-by=memory

# 4. Services, DNS, Endpoints & NetworkPolicies
kubectl get svc,endpoints,endpointslices -n <namespace>
kubectl get ingress,networkpolicies -n <namespace>
kubectl exec -it <pod-name> -n <namespace> -- nslookup kubernetes.default.svc.cluster.local

# 5. Storage & Rollouts
kubectl get pv,pvc,storageclass -A
kubectl rollout status deployment/<name> -n <namespace>
kubectl rollout history deployment/<name> -n <namespace>
kubectl get pdb -A
```

### Layer 2: Node, Container Runtime & Linux Kernel Investigation (Below Kubernetes)

```bash
# 1. Kubelet & Container Runtime Daemons
sudo systemctl status kubelet containerd --no-pager
sudo journalctl -u kubelet -xe --no-pager | tail -n 50
sudo journalctl -u containerd -xe --no-pager | tail -n 50

# 2. CRI-level Container & Pod Sandbox Inspection (Works even when API Server is down)
sudo crictl pods
sudo crictl ps -a
sudo crictl logs <container-id>
sudo crictl inspect <container-id>

# 3. Control Plane Static Pods & PKI Certificates
ls -la /etc/kubernetes/manifests/
sudo kubeadm certs check-expiration
sudo openssl x509 -in /var/lib/kubelet/pki/kubelet-client-current.pem -noout -text

# 4. Linux Networking (Namespaces, Sockets, Routes, iptables, conntrack, Packet Capture)
ip addr
ip route
ss -tulpn
sudo iptables-save | grep -i <service-name>
sudo conntrack -L | head -n 30
sudo tcpdump -ni any port 53 or port 80 -c 50
# Enter a container's network namespace from the host:
PID=$(sudo crictl inspect --output go-template --template '{{.info.pid}}' <container-id>)
sudo nsenter -t "${PID}" -n ip addr

# 5. Linux Memory, OOM Killer & Filesystem Pressure
free -h
df -h
df -i
sudo dmesg -T | grep -i -E 'oom|killed process|out of memory'
```
