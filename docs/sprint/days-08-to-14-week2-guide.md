# Week 2 Walkthrough Guide (Days 8–14) & 90-Day CKA / SRE Master Plan

This guide covers **Days 8 through 14** of the [14-Day Kubernetes Engineering Sprint](README.md), the **Day 14 Production Capstone**, and the **90-Day CKA & Platform Engineering Progression**.

---

## Day 8 (Nov 9): Kubernetes Storage (`PV`, `PVC`, `StorageClass`, `StatefulSet`)

### 1. Conceptual Check (35 min)
- **Why ephemeral container filesystems lose data**: Container writable layers (`overlayfs`) are tied to the container's lifecycle; when a Pod is deleted or rescheduled to another node, that writable layer is destroyed.
- **Static vs. Dynamic Provisioning**:
  - **Static**: An admin pre-creates a `PersistentVolume` (`PV`), and a user's `PersistentVolumeClaim` (`PVC`) binds to it.
  - **Dynamic**: A `PVC` references a `StorageClass`, and the **CSI (Container Storage Interface)** provisioner dynamically creates the backing storage volume and `PV`, then attaches/mounts it into the Pod.

### 2. Hands-On & Troubleshooting Lab (125 min)
1. Deploy the `Barnacles` `StatefulSet` ([`03-server-statefulset.yaml`](../../kubernetes/platform-barnacles/03-server-statefulset.yaml)) or test persistent storage survival across Pod deletion.
2. Execute **[Lab 09 (`PVC Pending` & StorageClass Troubleshooting)](../labs/lab-09-pvc-pending-storage.md)**:
   ```bash
   ./scripts/troubleshooting/sre-lab-runner.sh inject 09
   ./scripts/troubleshooting/sre-lab-runner.sh verify 09
   ```

---

## Day 9 (Nov 10): Kubernetes Security, RBAC & Pod Security Standards

### 1. Conceptual Check (35 min)
- **Authentication vs. Authorization vs. Admission Control**: Every API request passes through (1) **AuthN** (Who are you? X.509 client cert, ServiceAccount JWT, OIDC), (2) **AuthZ / RBAC** (Are you allowed to perform `verb` on `resource` in `namespace`?), and (3) **Admission Controllers** (Does the object comply with Pod Security Standards, ResourceQuotas, and policy webhooks?).
- **Least Privilege**: `Role` + `RoleBinding` grant permissions inside a single namespace; `ClusterRole` + `ClusterRoleBinding` grant permissions cluster-wide.

### 2. Hands-On Lab (125 min)
Create a namespace-scoped developer identity and verify permissions with `kubectl auth can-i`:
```bash
kubectl create namespace team-alpha
kubectl create serviceaccount alpha-deployer -n team-alpha
kubectl create role alpha-app-manager \
  --verb=get,list,watch,create,update,patch,delete \
  --resource=pods,deployments,services \
  -n team-alpha
kubectl create rolebinding alpha-deployer-binding \
  --role=alpha-app-manager \
  --serviceaccount=team-alpha:alpha-deployer \
  -n team-alpha

# Verify allowed vs. denied actions using impersonation:
kubectl auth can-i create deployments -n team-alpha --as=system:serviceaccount:team-alpha:alpha-deployer
# -> yes
kubectl auth can-i delete nodes --as=system:serviceaccount:team-alpha:alpha-deployer
# -> no
kubectl auth can-i list secrets -n kube-system --as=system:serviceaccount:team-alpha:alpha-deployer
# -> no

# Apply Restricted Pod Security Standards from kubernetes/security/:
kubectl apply -f kubernetes/security/pod-security-standards/restricted-namespace.yaml
kubectl delete namespace team-alpha
```

---

## Day 10 (Nov 11): Cluster Administration with `kubeadm`

### 1. Conceptual Check (35 min)
- **What happens to running workloads if `kube-apiserver` goes down?**
  - Existing Pods on worker nodes **continue running and serving traffic normally** because `containerd` and the Linux kernel/CNI data plane do not depend on `kube-apiserver` for already-started processes. However, no new Pods can be scheduled, no scaling/reconciliation can occur, and `kubectl` commands fail until the control plane is restored.

### 2. Hands-On & Troubleshooting Lab (125 min)
1. Inspect PKI certificate expiration and static pod manifests on your control plane:
   ```bash
   sudo kubeadm certs check-expiration
   ls -la /etc/kubernetes/manifests/
   ```
2. Practice automated `etcd` backup and restore using [`scripts/disaster-recovery/etcd-backup.sh`](../../scripts/disaster-recovery/etcd-backup.sh) and [`etcd-restore.sh`](../../scripts/disaster-recovery/etcd-restore.sh) (guide: [`docs/operations/etcd-backup-restore.md`](../operations/etcd-backup-restore.md)).
3. Practice zero-downtime `cordon`/`drain` and rolling upgrades using [`scripts/operations/rolling-upgrade.sh`](../../scripts/operations/rolling-upgrade.sh) (guide: [`docs/operations/cluster-upgrades.md`](../operations/cluster-upgrades.md)).
4. Execute **[Lab 02 (`etcd` Quorum Loss)](../labs/lab-02-etcd-quorum-loss.md)** and **[Lab 03 (`kubelet` Cert Failure)](../labs/lab-03-kubelet-cert-expiry.md)**.

---

## Day 11 (Nov 12): SRE Troubleshooting Methodology

### 1. Conceptual Check (35 min)
- **Never start by deleting a failing Pod.** Deleting a Pod destroys ephemeral evidence (in-memory state, previous container logs if not captured, netns sockets).
- **The 5-Step SRE Diagnostic Loop**:
  1. **Observe Symptoms** (`kubectl get pods -A`, `kubectl get events -A --sort-by=.metadata.creationTimestamp`).
  2. **Form Hypothesis** (Control Plane vs. Scheduler vs. Node/Kubelet vs. CNI/DNS vs. Application).
  3. **Collect Evidence** (`kubectl describe`, `kubectl logs --previous`, `journalctl -u kubelet`, `crictl`, `ss`, `iptables`).
  4. **Remediate Root Cause** (Fix the underlying config, resource, or service—not the symptom).
  5. **Verify & Document** (`sre-lab-runner.sh verify` + [`incident-report-template.md`](../labs/incident-report-template.md)).

### 2. Hands-On Lab (145 min)
Complete **[Lab 04 (`DiskPressure`)](../labs/lab-04-node-pressure-disk-full.md)** and work through labs `05` through `10` in [`docs/labs/README.md`](../labs/README.md) without hints.

---

## Day 12 (Nov 13): Advanced Failure Scenarios & Blind Timed Drills

Run **3 consecutive random blind fault-injection drills** and resolve each within **20–25 minutes**:
```bash
# Blind Drill #1
./scripts/troubleshooting/sre-lab-runner.sh random
# Investigate, fix, and check:
./scripts/troubleshooting/sre-lab-runner.sh status
```
Write a concise post-mortem for each drill using [`docs/labs/incident-report-template.md`](../labs/incident-report-template.md).

---

## Day 13 (Nov 14): Observability, SLIs, SLOs & Error Budgets

### 1. Conceptual Check (35 min)
- **The Four Golden Signals (Google SRE)**: **Latency** (P50/P95/P99), **Traffic** (requests/sec or tokens/sec), **Errors** (5xx rate / failed requests), and **Saturation** (CPU, memory, disk, KV cache %, queue depth).
- **SLI vs. SLO vs. Error Budget**:
  - **SLI (Indicator)**: Quantitative measurement (e.g., `99.4%` of `/v1/chat/completions` requests achieve `TTFT < 1.5s`).
  - **SLO (Objective)**: Target threshold (`>= 99.5%` over 28 days).
  - **Error Budget**: `100% - SLO` (`0.5%` allowed unreliability before freezing feature rollouts to prioritize reliability).

### 2. Hands-On Lab (145 min)
Deploy the cluster observability stack, Level 5 AI Inference rules, and `Barnacles` platform rules:
```bash
kubectl apply -f kubernetes/observability/
kubectl apply -f kubernetes/ai-inference/04-prometheus-inference-rules.yaml
kubectl apply -f kubernetes/platform-barnacles/06-prometheus-barnacles-rules.yaml
kubectl get pods,cm -n observability
```

---

## Day 14 (Nov 15): End-to-End Production Capstone

Choose **either** (or both) flagship capstone architectures in this repository:
1. **Capstone Track A — `Barnacles` Distributed Log Platform (`kubernetes/platform-barnacles/`)**:
   - Follow the 10-step runbook in [`docs/architecture/barnacles-platform.md`](../architecture/barnacles-platform.md).
2. **Capstone Track B — Level 5 `vLLM` AI Inference Platform (`kubernetes/ai-inference/`)**:
   - Deploy `01` through `05` in `kubernetes/ai-inference/`, run `./scripts/ai-inference/benchmark-inference.sh`, inject a gateway or readiness fault, recover service, and measure `TTFT`, `Tokens/sec`, and `$/1M tokens`.

---

## Beyond Day 14: 90-Day Development & CKA Certification Plan (Nov 2026 – Jan 2027)

| Phase | Calendar Window | Primary Focus | Readiness Gate / Deliverable |
| :--- | :--- | :--- | :--- |
| **Sprint 1** | Nov 2 – Nov 15 | **Days 1–14: Kubernetes Internals & Core Operations** | Complete all 14 daily labs + 10 SRE scenarios (`sre-lab-runner.sh`). |
| **Sprint 2** | Nov 16 – Nov 30 | **Days 16–30: HA Administration, PKI, Storage & RBAC** | Bootstrap `level2-ha` & `level3-hardened`; perform live `etcd` snapshot/restore & rolling upgrade. |
| **Sprint 3** | Dec 1 – Dec 15 | **Days 31–45: Networking Deep Dive & Timed CKA Drills** | Complete [30-Day Networking Roadmap](../networking/30-day-networking-roadmap.md) & solve any CKA troubleshooting task in `< 8 mins`. |
| **Sprint 4** | Dec 16 – Dec 31 | **CKA Exam Readiness & Certification Milestone** | Score **`80–85%+`** on two consecutive 2-hour timed mock exams (`Killer.sh`), then sit the **CKA Exam**. |
| **Sprint 5** | Jan 1 – Jan 31, 2027 | **Days 61–90: GitOps, `Barnacles` Platform & Chaos Engineering** | Automate `Barnacles` delivery via Argo CD (`kubernetes/platform-barnacles/`) & publish SRE incident portfolio. |
| **Sprint 6** | Feb – Apr 2027 | **AI Systems & `vLLM` Inference Infrastructure** | Transition Level 5 `vLLM` platform (`kubernetes/ai-inference/`) from CPU to GPU (`nvidia-l4`), tune KV cache & batching, and benchmark `$/1M tokens`. |
