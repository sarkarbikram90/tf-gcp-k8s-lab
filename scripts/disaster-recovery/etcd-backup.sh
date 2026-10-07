#!/usr/bin/env bash
# ==============================================================================
# Script: etcd-backup.sh
# Purpose: Takes a consistent etcd snapshot and uploads it to Google Cloud Storage
# Target: Run on ANY Control Plane node (requires root / sudo permissions)
# ==============================================================================

set -euo pipefail

BACKUP_DIR="/var/backups/etcd"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
SNAPSHOT_FILE="${BACKUP_DIR}/etcd-snapshot-${TIMESTAMP}.db"
GCS_BUCKET="${1:-}" # Optional GCS bucket name: e.g. "gs://my-k8s-backup-bucket"

# Ensure local backup directory exists
sudo mkdir -p "${BACKUP_DIR}"

echo "==> [1/4] Taking etcd snapshot..."
sudo ETCDCTL_API=3 etcdctl snapshot save "${SNAPSHOT_FILE}" \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

echo "==> [2/4] Verifying snapshot status and integrity..."
sudo ETCDCTL_API=3 etcdctl snapshot status "${SNAPSHOT_FILE}" --write-out=table

echo "==> [3/4] Generating SHA256 checksum..."
sha256sum "${SNAPSHOT_FILE}" | sudo tee "${SNAPSHOT_FILE}.sha256"

if [[ -n "${GCS_BUCKET}" ]]; then
  echo "==> [4/4] Uploading snapshot to Google Cloud Storage (${GCS_BUCKET})..."
  gcloud storage cp "${SNAPSHOT_FILE}" "${GCS_BUCKET}/etcd-backups/"
  gcloud storage cp "${SNAPSHOT_FILE}.sha256" "${GCS_BUCKET}/etcd-backups/"
  echo "Backup successfully archived to GCS: ${GCS_BUCKET}/etcd-backups/etcd-snapshot-${TIMESTAMP}.db"
else
  echo "==> [4/4] GCS bucket not specified; local backup saved to ${SNAPSHOT_FILE}"
fi

# Rotate local backups: keep latest 7 days
sudo find "${BACKUP_DIR}" -name "etcd-snapshot-*.db*" -mtime +7 -delete 2>/dev/null || true

echo "===> etcd backup completed successfully!"
