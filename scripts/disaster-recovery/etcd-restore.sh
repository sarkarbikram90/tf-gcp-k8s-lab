#!/usr/bin/env bash
# ==============================================================================
# Script: etcd-restore.sh
# Purpose: Safely restores an etcd snapshot and recovers the Kubernetes cluster
# Target: Run on the Control Plane node to be restored
# Usage: sudo ./etcd-restore.sh <PATH_TO_SNAPSHOT_FILE>
# ==============================================================================

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Error: Snapshot file path required."
  echo "Usage: sudo $0 /var/backups/etcd/etcd-snapshot-YYYYMMDD_HHMMSS.db"
  exit 1
fi

SNAPSHOT_FILE="$1"
RESTORE_DATA_DIR="/var/lib/etcd-restored"
MANIFEST_DIR="/etc/kubernetes/manifests"
TEMP_MANIFEST_DIR="/etc/kubernetes/manifests-stopped"

if [[ ! -f "${SNAPSHOT_FILE}" ]]; then
  echo "Error: Snapshot file '${SNAPSHOT_FILE}' does not exist!"
  exit 1
fi

echo "==> [1/6] Verifying snapshot integrity..."
sudo ETCDCTL_API=3 etcdctl snapshot status "${SNAPSHOT_FILE}" --write-out=table

echo "==> [2/6] Stopping static control-plane pods..."
sudo mkdir -p "${TEMP_MANIFEST_DIR}"
if [[ -f "${MANIFEST_DIR}/kube-apiserver.yaml" ]]; then
  sudo mv "${MANIFEST_DIR}/kube-apiserver.yaml" "${TEMP_MANIFEST_DIR}/"
fi
if [[ -f "${MANIFEST_DIR}/etcd.yaml" ]]; then
  sudo mv "${MANIFEST_DIR}/etcd.yaml" "${TEMP_MANIFEST_DIR}/"
fi

# Wait a few seconds for containers to stop
sleep 5

echo "==> [3/6] Restoring snapshot to temporary data directory (${RESTORE_DATA_DIR})..."
sudo rm -rf "${RESTORE_DATA_DIR}"
sudo ETCDCTL_API=3 etcdctl snapshot restore "${SNAPSHOT_FILE}" \
  --data-dir="${RESTORE_DATA_DIR}"

echo "==> [4/6] Backing up corrupted/old etcd directory and swapping in restored data..."
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
if [[ -d "/var/lib/etcd" ]]; then
  sudo mv /var/lib/etcd "/var/lib/etcd.bak.${TIMESTAMP}"
fi
sudo mv "${RESTORE_DATA_DIR}" /var/lib/etcd

# Ensure proper ownership
sudo chown -R root:root /var/lib/etcd

echo "==> [5/6] Restarting control-plane static pods..."
sudo mv "${TEMP_MANIFEST_DIR}/etcd.yaml" "${MANIFEST_DIR}/"
sudo mv "${TEMP_MANIFEST_DIR}/kube-apiserver.yaml" "${MANIFEST_DIR}/"
sudo rmdir "${TEMP_MANIFEST_DIR}" 2>/dev/null || true

echo "==> [6/6] Waiting for kube-apiserver to resume healthy operations..."
for i in {1..30}; do
  if kubectl get nodes &>/dev/null; then
    echo "Cluster is healthy!"
    kubectl get nodes
    exit 0
  fi
  echo "Waiting for API server... ($i/30)"
  sleep 3
done

echo "Warning: API server did not respond within 90 seconds. Check 'crictl ps' and '/var/log/pods/' for logs."
