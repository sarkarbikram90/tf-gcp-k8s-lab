# Lab 02: etcd Quorum Loss & Recovery

## Objective
Diagnose an HA cluster that has lost etcd consensus quorum due to multiple node outages and restore write availability.

---

## Failure Symptoms
1. `kubectl` commands time out or return:
   ```text
   Error from server: etcdserver: leader changed / context deadline exceeded
   ```
2. The Kubernetes API server fails liveness/readiness probes.

---

## Diagnosis Workflow

### Step 1: Check etcd Endpoint Health
On a control plane node:
```bash
sudo ETCDCTL_API=3 etcdctl endpoint health \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  --write-out=table
```

### Step 2: List Cluster Members
```bash
sudo ETCDCTL_API=3 etcdctl member list \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  --write-out=table
```
Check if members are unreachable or partition splits have occurred.

---

## Remediation

### Scenario A: Reviving Offline Members
1. Inspect the VM status in Google Cloud:
   ```bash
   gcloud compute instances list --filter="tags.items:k8s-control-plane"
   ```
2. Restart any stopped instances or restart `containerd`:
   ```bash
   sudo systemctl restart containerd
   ```

### Scenario B: Restoring from Disaster Recovery Snapshot
If two members are permanently unrecoverable, follow [`docs/operations/etcd-backup-restore.md`](../operations/etcd-backup-restore.md) to restore from the latest snapshot and reset cluster membership.
