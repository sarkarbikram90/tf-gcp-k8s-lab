# Lab 15: CKS Runtime Syscall Breach, `Falco` Detection & Forensic Pod Quarantine

> **Domain:** CKS — Monitoring, Logging & Runtime Security (20%) & Cluster Setup / NetworkPolicies (15%)  
> **Target MTTR:** `< 10 minutes`  
> **Automated Injection:** `./scripts/troubleshooting/sre-lab-runner.sh inject 15`

---

## 1. Incident Symptom & Alert Signal

A `Falco` modern eBPF sensor (`kubernetes/security/runtime-security/01-falco-ebpf-runtime-defense.yaml`) fires a `CRITICAL` runtime security alert to `sre-copilot`:

```json
{
  "output": "CKS_ALERT [SensitiveFileRead] Sensitive credential or PKI file read (file=/etc/shadow pod=compromised-debug-pod ns=sre-lab)",
  "priority": "CRITICAL",
  "rule": "CKS Sensitive Credential or PKI File Read in Container",
  "output_fields": {
    "k8s.ns.name": "sre-lab",
    "k8s.pod.name": "compromised-debug-pod"
  }
}
```

### The CKS Forensic Golden Rule
**Never immediately `kubectl delete pod` a suspected compromised container** unless instructed. Deleting the pod destroys volatile process memory, open sockets, unlinked binaries in `/proc/<pid>/exe`, and `/tmp` artifacts before CKS incident responders can inspect them.

Instead, **forensically quarantine the pod in-place**:
1. Relabel the compromised pod with `security.platform.io/quarantine=isolated` (either manually or via `sre-copilot`'s `POST /incidents/{id}/remediate` endpoint).
2. Enforce a zero-trust `NetworkPolicy` that selects `security.platform.io/quarantine: isolated` and blocks **both `Ingress` and `Egress`** (including DNS `:53`).

---

## 2. First-Principles Investigation

### Step 1: Inspect the Compromised Pod & Logs
```bash
kubectl get pod compromised-debug-pod -n sre-lab --show-labels
kubectl logs compromised-debug-pod -n sre-lab
```
Observe that `compromised-debug-pod` has label `security.platform.io/quarantine=unisolated`.

### Step 2: Inspect the Quarantine `NetworkPolicy`
```bash
kubectl get networkpolicy cks-quarantine-isolation -n sre-lab -o yaml
```
Identify two critical security bugs in `cks-quarantine-isolation`:
1. **Selector Mismatch:** `spec.podSelector.matchLabels` targets `security.platform.io/quarantine: wrong-quarantine-label` instead of `isolated`.
2. **Missing Egress Isolation:** `spec.policyTypes` only lists `Ingress`, leaving outbound `Egress` wide open for credential or model-weight exfiltration.

---

## 3. Remediation

### Step 1: Enforce Zero-Trust `Ingress` + `Egress` Quarantine Policy
```bash
kubectl apply -n sre-lab -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: cks-quarantine-isolation
  labels:
    sre-lab: "15"
spec:
  podSelector:
    matchLabels:
      security.platform.io/quarantine: isolated
  policyTypes:
    - Ingress
    - Egress
  ingress: []
  egress: []
EOF
```

### Step 2: Quarantine the Compromised Pod In-Place (Keep `Running` for Forensics)
```bash
kubectl label pod compromised-debug-pod -n sre-lab \
  security.platform.io/quarantine=isolated --overwrite
```
*(In production with `sre-copilot` running, calling `curl -X POST http://sre-copilot.sre-copilot.svc:8080/incidents/inc-1/remediate -d '{"action":"quarantine_pod"}'` executes this Strategic Merge Patch automatically.)*

---

## 4. Verification

Run the automated verifier to confirm `compromised-debug-pod` is still `Running` (forensically preserved) and isolated under both `Ingress` and `Egress` quarantine:

```bash
./scripts/troubleshooting/sre-lab-runner.sh verify 15
```
