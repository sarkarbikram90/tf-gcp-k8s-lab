# Lab 13: Level 6 IDP Governance — Kyverno Hygiene & Restricted PSS Violations

## Objective
Audit and remediate a non-compliant developer workload (`rogue-tenant-service`) that bypassed the **[Level 6 IDP Golden Path](../architecture/level-6-idp.md)** and violates three platform admission policies ([`03-validate-workload-hygiene.yaml`](../../kubernetes/platform-idp/kyverno/03-validate-workload-hygiene.yaml)):
1. Missing the mandatory FinOps/ownership label `idp.k8s-lab.internal/owner-team`.
2. Using a mutable `:latest` container image tag (`busybox:latest`).
3. Missing Kubernetes `restricted` Pod Security Standard controls (`runAsNonRoot: true`, non-root UID `65532`).

---

## First-Principles Mental Model
In a multi-tenant Internal Developer Platform (IDP):
- **Why `:latest` is banned**: Mutable tags break GitOps reproducibility, prevent deterministic `kubectl rollout undo` rollbacks, and make vulnerability attribution impossible.
- **Why `idp.k8s-lab.internal/owner-team` is required**: Every alert and cloud cost metric must route to an accountable engineering squad.
- **Why `runAsNonRoot: true` is enforced**: Prevents container processes from running as UID `0` on the underlying Linux kernel.

---

## Automated Failure Injection

```bash
./scripts/troubleshooting/sre-lab-runner.sh inject 13
```

---

## Diagnosis Workflow

Inspect the non-compliant Deployment in `sre-lab`:
```bash
kubectl get deploy rogue-tenant-service -n sre-lab -o yaml
```
Identify the three policy violations:
1. `.metadata.labels` lacks `idp.k8s-lab.internal/owner-team`.
2. `.spec.template.spec.containers[0].image` is `busybox:latest`.
3. `.spec.template.spec.securityContext.runAsNonRoot` is unset.

---

## Remediation

Patch `rogue-tenant-service` to comply with Level 6 IDP Golden Path standards:
```bash
kubectl label deployment rogue-tenant-service -n sre-lab idp.k8s-lab.internal/owner-team=checkout-engineering --overwrite

kubectl patch deployment rogue-tenant-service -n sre-lab --type='merge' -p '{
  "spec": {
    "template": {
      "spec": {
        "securityContext": {
          "runAsNonRoot": true,
          "runAsUser": 65532,
          "runAsGroup": 65532,
          "seccompProfile": {
            "type": "RuntimeDefault"
          }
        },
        "containers": [
          {
            "name": "app",
            "image": "busybox:1.36",
            "securityContext": {
              "allowPrivilegeEscalation": false,
              "capabilities": {
                "drop": ["ALL"]
              }
            }
          }
        ]
      }
    }
  }
}'
```

### Verify Compliance
```bash
./scripts/troubleshooting/sre-lab-runner.sh verify 13
```
