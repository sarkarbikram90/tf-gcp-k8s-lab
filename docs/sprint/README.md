# 14-Day Kubernetes Engineering Sprint & AI Infrastructure Roadmap (`docs/sprint`)

> **Strategic Goal (2026–2027):** Become an **AI Systems & Inference Infrastructure Engineer** by combining deep Kubernetes & Linux systems mastery with distributed model-serving (`vLLM`), observability, and token economics.
>
> **Career Progression:** `Kubernetes Engineer → Platform Engineer → AI Infrastructure Engineer → AI Systems / Inference Infrastructure Engineer`

---

## 1. Strategic Timeline (Nov 2026 – Apr 2027)

| Timeline | Primary Objective | Core Deliverables in `tf-gcp-k8s-lab` & `Barnacles` |
| :--- | :--- | :--- |
| **Nov 2 – Nov 15, 2026** | **14-Day Kubernetes Sprint (42 hrs)** | First-principles mastery, daily hands-on labs, 10 SRE troubleshooting scenarios |
| **Nov 16 – Dec 31, 2026** | **Cluster Administration & CKA** | Level 2 HA + Level 3 Hardening mastery, timed mock exams (`80–85%+`), CKA exam |
| **January 2027** | **Platform Engineering** | Terraform automation, Helm/Kustomize, Argo CD GitOps, `Barnacles` production delivery |
| **February 2027** | **AI Workloads & Model Serving** | Level 5 LLM Inference Platform (`vLLM` CPU → GPU), LLM Gateway, model cache PVCs |
| **March – April 2027** | **Inference Infrastructure & Economics** | TTFT & tokens/sec optimization, KV cache tuning, HPA/GPU scaling, cost per 1M tokens |

---

## 2. Daily 180-Minute Engineering Routine

Commit **3 hours/day** for 14 consecutive days. Every single day must produce a tangible engineering artifact (a working deployment, a post-mortem incident report, an architecture diagram, or a verified configuration):

| Time Block | Duration | Share | Activity |
| :--- | :---: | :---: | :--- |
| **1. Conceptual Understanding** | `35 min` | `19%` | Read upstream Kubernetes docs, trace component responsibilities, answer the 5 first-principles questions. |
| **2. Hands-On Engineering** | `100 min` | `56%` | Build, deploy, inspect, and experiment directly on `tf-gcp-k8s-lab`. |
| **3. Troubleshooting & Chaos** | `25 min` | `14%` | Break something deliberately or run `./scripts/troubleshooting/sre-lab-runner.sh` and diagnose from evidence. |
| **4. Engineering Journal** | `20 min` | `11%` | Record what worked, what failed, commands run, and open questions using [`journal-template.md`](journal-template.md). |

---

## 3. 14-Day Sprint Tracker & Daily Curriculum (Nov 2 – Nov 15)

### Week 1: Understand How Kubernetes Works Internally

| Day | Date | Focus Topic | Hands-On Lab & Associated Repo Assets | End-of-Day Verification Question | Status |
| :--- | :--- | :--- | :--- | :--- | :---: |
| **Day 1** | Nov 2 | **Linux, Containers & K8s Architecture** | Inspect Linux namespaces (`lsns`), cgroups (`/sys/fs/cgroup`), `containerd` (`crictl`), `kubelet`, and static pods. Guide: **[Day 1 Walkthrough](day-01-walkthrough.md)** | *What happens step-by-step when Kubernetes receives a request to run a container?* | `[ ]` |
| **Day 2** | Nov 3 | **API Server, `etcd` & Reconciliation** | Create raw Pod vs. Deployment YAML; delete a Pod and watch `deployment-controller` + `replicaset-controller` reconcile via `kubectl get events -w`. | *What is the architectural difference between an unmanaged Pod and a Deployment-managed Pod?* | `[ ]` |
| **Day 3** | Nov 4 | **Pods, ReplicaSets & Deployments** | Scale Nginx `1 → 5`, perform rolling update & rollback; run **[Lab 05 (`CrashLoopBackOff` & `ImagePullBackOff`)](../labs/lab-05-crashloop-and-imagepull.md)**. | *What happens internally in etcd and controllers when you scale a Deployment from 2 to 5 replicas?* | `[ ]` |
| **Day 4** | Nov 5 | **Scheduling & Resource Management** | Test CPU/Memory requests vs. limits, QoS classes, Taints/Tolerations, Affinity; run **[Lab 06 (`Pending` Pods)](../labs/lab-06-pending-pods-scheduling.md)** & **[Lab 07 (`OOMKilled`)](../labs/lab-07-oomkilled-memory-limits.md)**. | *Why can a Pod remain `Pending` even when every worker node reports `Ready`?* | `[ ]` |
| **Day 5** | Nov 6 | **Networking Fundamentals** | Trace Pod-to-Pod & Pod-to-Service traffic, CNI (Flannel), `kube-proxy` (`iptables`), `CoreDNS`, `EndpointSlices`; run **[Lab 01 (Broken CNI)](../labs/lab-01-broken-cni.md)**. | *How does a packet reach a Pod when the client only knows the Kubernetes Service name?* | `[ ]` |
| **Day 6** | Nov 7 | **Ingress, Gateway API & NetworkPolicies** | Configure North-South Ingress & East-West `NetworkPolicy` isolation (`kubernetes/security/network-policies/`); run **[Lab 08 (Service & NetPol Blackhole)](../labs/lab-08-service-networking-and-dns.md)**. | *Why does creating an `Ingress` resource alone not expose an application externally?* | `[ ]` |
| **Day 7** | Nov 8 | **Configuration & Application Lifecycle** | Inject `ConfigMaps`/`Secrets` (env & mounted volumes); test `startupProbe`, `readinessProbe`, and `livenessProbe`; run **[Lab 10 (Stuck Rollouts & Probes)](../labs/lab-10-stuck-rollout-and-probes.md)**. | *How does Kubernetes decide whether a container should stop receiving traffic vs. be restarted?* | `[ ]` |

### Week 2: Think Like a Kubernetes Administrator & SRE

| Day | Date | Focus Topic | Hands-On Lab & Associated Repo Assets | End-of-Day Verification Question | Status |
| :--- | :--- | :--- | :--- | :--- | :---: |
| **Day 8** | Nov 9 | **Kubernetes Storage (`PV`, `PVC`, `CSI`)** | Provision `PV`/`PVC`, `StorageClasses`, `StatefulSets`; delete Pod and verify data survival; run **[Lab 09 (`PVC Pending`)](../labs/lab-09-pvc-pending-storage.md)**. | *Why does a standard container root filesystem not guarantee data persistence across restarts?* | `[ ]` |
| **Day 9** | Nov 10 | **Kubernetes Security & RBAC** | Create namespace-scoped `ServiceAccount`, `Role`, `RoleBinding`; test with `kubectl auth can-i`; apply Restricted PSS (`kubernetes/security/pod-security-standards/`). | *Why should workloads never run with the default `cluster-admin` or root container identity?* | `[ ]` |
| **Day 10** | Nov 11 | **Cluster Administration with `kubeadm`** | Practice `etcd` backup/restore (`scripts/disaster-recovery/`), PKI checks, `cordon`/`drain`, rolling upgrades (`scripts/operations/`); run **[Lab 02](../labs/lab-02-etcd-quorum-loss.md)** & **[Lab 03](../labs/lab-03-kubelet-cert-expiry.md)**. | *What happens to already-running application Pods on worker nodes if `kube-apiserver` goes down?* | `[ ]` |
| **Day 11** | Nov 12 | **SRE Troubleshooting Methodology** | Run **[Lab 04 (`DiskPressure`)](../labs/lab-04-node-pressure-disk-full.md)** and systematically complete any remaining scenarios in [`docs/labs/README.md`](../labs/README.md) without hints. | *Why is `kubectl delete pod` an anti-pattern during initial incident triage?* | `[ ]` |
| **Day 12** | Nov 13 | **Advanced Failure Scenarios & Blind Drills** | Run 3 consecutive blind timed drills (`./scripts/troubleshooting/sre-lab-runner.sh random`) under 25 minutes each and write incident reports ([template](../labs/incident-report-template.md)). | *How do you quickly distinguish an application bug from a node, CNI, or control-plane failure?* | `[ ]` |
| **Day 13** | Nov 14 | **Observability & Reliability Engineering** | Deploy `kubernetes/observability/` (Prometheus alerts, `node-exporter`) and Level 5 AI Inference rules (`kubernetes/ai-inference/04-prometheus-inference-rules.yaml`). | *Which Golden Signals and SLO indicators detect service degradation before users page on-call?* | `[ ]` |
| **Day 14** | Nov 15 | **End-to-End Production Capstone** | Deploy the Level 5 LLM Inference Platform (`kubernetes/ai-inference/`) or multi-tier API + Redis stack with storage, RBAC, probes, NetworkPolicies, monitoring, fault injection & recovery. | *Can you walk through the complete request & control loop path and recover from an injected failure live?* | `[ ]` |

---

## 4. Kubernetes & AI Systems Competency Scorecard

Self-assess each domain from `0` (unfamiliar) to `5` (can design, operate, and debug under production failure without tutorials):

| Competency Domain | Weight | Score (`0–5`) | Target Milestone |
| :--- | :---: | :---: | :--- |
| **1. Kubernetes Architecture & Internals** (`apiserver`, `etcd`, `scheduler`, `kubelet`, `CRI`) | `15%` | `0 / 5` | Days 1–4 |
| **2. Cluster Installation & Administration** (`kubeadm`, HA, PKI, upgrades, `etcd` DR) | `15%` | `0 / 5` | Day 10 + Level 2/3 |
| **3. Networking & Storage** (CNI, `CoreDNS`, `iptables`, `NetworkPolicy`, `PV`/`PVC`/CSI) | `15%` | `0 / 5` | Days 5, 6, 8 |
| **4. Troubleshooting & Incident Response** (10-scenario lab suite & blind drills) | `20%` | `0 / 5` | Days 11–12 (`docs/labs/`) |
| **5. Security & Access Management** (RBAC, PSS, KMS encryption, audit logging, WIF) | `10%` | `0 / 5` | Day 9 + Level 3 |
| **6. Observability & Reliability Engineering** (Prometheus, Grafana, SLIs/SLOs, alerts) | `10%` | `0 / 5` | Day 13 + Level 4 |
| **7. Infrastructure Automation & GitOps** (Terraform, GitHub Actions WIF, Helm/Argo CD) | `10%` | `0 / 5` | Level 1–4 + Jan 2027 |
| **8. AI Inference Infrastructure & Token Economics** (`vLLM`, TTFT, TPS, KV cache, GPU/CPU) | `5%` | `0 / 5` | Level 5 (`kubernetes/ai-inference/`) |
