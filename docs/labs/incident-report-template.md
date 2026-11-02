# SRE Post-Mortem & Incident Report Template

Copy this template whenever you complete a troubleshooting lab or resolve a failure injection drill. Building a library of structured incident reports proves production SRE readiness.

---

```markdown
# Incident Report: [INC-YYYYMMDD-XX] <Short Descriptive Title>

- **Date:** YYYY-MM-DD
- **Lab / Scenario ID:** Lab XX (or Blind Random Drill)
- **Responder:** Bikram Sarkar
- **Time to Detect (TTD):** XX minutes
- **Time to Mitigate / Recover (TTR):** XX minutes
- **Severity:** SEV-1 / SEV-2 / SEV-3

---

## 1. Executive Summary & User Impact
- **What broke?** (e.g., `orders-svc` returned 100% connection timeouts to `frontend-client`; or `checkout-api` failed all pod startups.)
- **Blast radius:** Which namespaces, services, or nodes were impacted?

---

## 2. Symptoms & Detection
- **How was the failure detected?** (Prometheus alert, `kubectl get pods`, synthetic probe failure, node condition status.)
- **Observed error messages:**
  ```text
  <Paste exact symptom output or event message here>
  ```

---

## 3. Initial Hypothesis (First-Principles Reasoning)
- **Which Kubernetes/Linux component owns this stage of the lifecycle?**
- **Initial hypotheses formed before making changes:**
  1. Hypothesis A: ...
  2. Hypothesis B: ...

---

## 4. Investigation Timeline & Commands Executed
| Timestamp | Layer (K8s / Node / Linux) | Command Executed | Finding / Observation |
| :--- | :--- | :--- | :--- |
| `00:00` | K8s API | `kubectl get pods -n sre-lab` | Observed `0/1 Ready` / `CrashLoopBackOff` |
| `00:03` | K8s Events | `kubectl describe pod ...` | Found `Readiness probe failed: HTTP 404` |
| `00:07` | Node / Spec | `kubectl get deploy ... -o yaml` | Identified wrong probe path `/healthz-typo` |

---

## 5. Evidence Collected
```text
<Paste key kubectl describe / logs / journalctl / dmesg / iptables snippet that proved the root cause>
```

---

## 6. Root Cause & Contributing Factors
- **Primary Root Cause:**
- **Contributing Factors:** (e.g., missing CI validation, absent `startupProbe`, unbounded memory allocation, missing `StorageClass` check.)

---

## 7. Remediation & Recovery Validation
- **Corrective Action Taken:**
  ```bash
  <Exact commands or manifest changes applied>
  ```
- **How Recovery Was Verified:**
  ```bash
  ./scripts/troubleshooting/sre-lab-runner.sh verify <lab-id>
  ```

---

## 8. Preventive Actions (Action Items)
- [ ] **Automation / Policy Gate:** (e.g., Add Trivy/Kyverno admission check or CI manifest lint)
- [ ] **Observability Alert:** (e.g., Add Prometheus alert rule for `kube_pod_container_status_restarts_total` or `kube_persistentvolumeclaim_status_phase`)
```
