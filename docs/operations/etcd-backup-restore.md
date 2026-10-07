# Disaster Recovery: etcd Backup & Restore Runbook

This runbook outlines the operational procedures for taking point-in-time etcd snapshots, verifying backup integrity, archiving to Google Cloud Storage (GCS), and performing a full disaster recovery restore.

---

## 1. Prerequisites
- SSH access to a Control Plane node via IAP (`gcloud compute ssh ... --tunnel-through-iap`).
- `etcdctl` binary available on the node (installed with Kubernetes tools).
- Node service account must have `roles/storage.objectAdmin` or `roles/storage.objectCreator` on the backup GCS bucket.

---

## 2. Taking an etcd Snapshot

### Automated Execution
Run [`scripts/disaster-recovery/etcd-backup.sh`](../../scripts/disaster-recovery/etcd-backup.sh):

```bash
# Local backup only:
sudo ./etcd-backup.sh

# Backup and upload to GCS:
sudo ./etcd-backup.sh gs://my-company-k8s-backups
```

### Manual Command
```bash
sudo ETCDCTL_API=3 etcdctl snapshot save /var/backups/etcd/snapshot-$(date +%F).db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key
```

Verify snapshot status:
```bash
sudo ETCDCTL_API=3 etcdctl snapshot status /var/backups/etcd/snapshot-$(date +%F).db --write-out=table
```

---

## 3. Restoring an etcd Snapshot (Disaster Recovery)

When restoring an etcd snapshot, you must prevent the API server from modifying data during the restore operation.

### Automated Restore
Run [`scripts/disaster-recovery/etcd-restore.sh`](../../scripts/disaster-recovery/etcd-restore.sh):

```bash
sudo ./etcd-restore.sh /var/backups/etcd/etcd-snapshot-YYYYMMDD_HHMMSS.db
```

### Step-by-Step Manual Recovery Procedure

1. **Stop Control Plane Pods**:
   Move static pod manifests out of `/etc/kubernetes/manifests`:
   ```bash
   sudo mkdir -p /etc/kubernetes/manifests-stopped
   sudo mv /etc/kubernetes/manifests/kube-apiserver.yaml /etc/kubernetes/manifests-stopped/
   sudo mv /etc/kubernetes/manifests/etcd.yaml /etc/kubernetes/manifests-stopped/
   ```

2. **Restore Snapshot to a Clean Directory**:
   ```bash
   sudo ETCDCTL_API=3 etcdctl snapshot restore /path/to/snapshot.db \
     --data-dir=/var/lib/etcd-restored
   ```

3. **Swap Data Directories**:
   ```bash
   sudo mv /var/lib/etcd /var/lib/etcd.bak.$(date +%s)
   sudo mv /var/lib/etcd-restored /var/lib/etcd
   sudo chown -R root:root /var/lib/etcd
   ```

4. **Restart Control Plane Pods**:
   Move manifests back to `/etc/kubernetes/manifests`:
   ```bash
   sudo mv /etc/kubernetes/manifests-stopped/* /etc/kubernetes/manifests/
   sudo rmdir /etc/kubernetes/manifests-stopped
   ```

5. **Verify Cluster Health**:
   ```bash
   kubectl get nodes
   kubectl get pods -A
   ```
