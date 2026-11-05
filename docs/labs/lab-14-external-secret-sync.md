# Lab 14: Level 6 Cloud Secrets — `ExternalSecret` & Secret Key Mapping Drift

## Objective
Diagnose and resolve a `CreateContainerConfigError` failure on a **[Level 6 IDP workload](../architecture/level-6-idp.md)** (`order-worker-idp`) caused by a mismatch between the Kubernetes `Secret` materialized by External Secrets Operator (`gcp-sm-order-api-synced`) and the `secretKeyRef` configured in the workload `Deployment`.

---

## First-Principles Mental Model
When syncing secrets from **Google Cloud Secret Manager** via **External Secrets Operator (`ESO`)**:
1. `ClusterSecretStore` authenticates to GCP Secret Manager using keyless Workload Identity / Node IAM.
2. `ExternalSecret` fetches the cloud payload and creates a target Kubernetes `Secret` (e.g., `gcp-sm-order-api-synced`).
3. The `kubelet` mounts or injects keys from that Kubernetes `Secret` prior to starting the container. If either the `Secret` name or the specific key name inside `.data` does not match `.env[].valueFrom.secretKeyRef`, `kubelet` halts container creation with **`CreateContainerConfigError`**.

---

## Automated Failure Injection

```bash
./scripts/troubleshooting/sre-lab-runner.sh inject 14
```

---

## Failure Symptoms
1. `kubectl get pods -n sre-lab -l app=order-worker-idp` shows `CreateContainerConfigError`.
2. `kubectl describe pod -n sre-lab -l app=order-worker-idp` reports:
   ```text
   Warning  Failed  kubelet  Error: secret "gcp-sm-order-api-missing-secret" not found
   ```

---

## Diagnosis Workflow

### Step 1: Inspect Available Secrets & Keys in the Namespace
```bash
kubectl get secrets -n sre-lab -l sre-lab=14
kubectl get secret gcp-sm-order-api-synced -n sre-lab -o jsonpath='{.data}'
```
Notice that the synced Secret is named `gcp-sm-order-api-synced` and exposes the key `DATABASE_URI`.

### Step 2: Compare Against Deployment `secretKeyRef`
```bash
kubectl get deploy order-worker-idp -n sre-lab -o jsonpath='{.spec.template.spec.containers[0].env}{"\n"}'
```
The Deployment points to `name: gcp-sm-order-api-missing-secret` and `key: DB_CONN_STRING_WRONG_KEY`.

---

## Remediation

Align the Deployment's `secretKeyRef` with the synced Secret `gcp-sm-order-api-synced` and key `DATABASE_URI`:
```bash
kubectl patch deployment order-worker-idp -n sre-lab --type='json' -p='[
  {"op": "replace", "path": "/spec/template/spec/containers/0/env/0/valueFrom/secretKeyRef/name", "value": "gcp-sm-order-api-synced"},
  {"op": "replace", "path": "/spec/template/spec/containers/0/env/0/valueFrom/secretKeyRef/key", "value": "DATABASE_URI"}
]'
kubectl rollout status deployment/order-worker-idp -n sre-lab --timeout=60s
```

### Verify Recovery
```bash
./scripts/troubleshooting/sre-lab-runner.sh verify 14
```
