#!/usr/bin/env bash
# ==============================================================================
# Script: rolling-upgrade.sh
# Purpose: Performs a rolling upgrade of a single Kubernetes node (Control Plane or Worker)
# Target: Run directly on the node being upgraded
# Usage: sudo ./rolling-upgrade.sh <TARGET_K8S_VERSION> [control-plane|worker]
# Example: sudo ./rolling-upgrade.sh 1.31.1-1.1 control-plane
# ==============================================================================

set -euo pipefail

TARGET_VERSION="${1:-}"
NODE_ROLE="${2:-worker}"

if [[ -z "${TARGET_VERSION}" ]]; then
  echo "Usage: sudo $0 <TARGET_VERSION> [control-plane|worker]"
  echo "Example: sudo $0 1.31.1-1.1 control-plane"
  exit 1
fi

NODE_NAME="$(hostname -s)"
echo "==> Upgrading node '${NODE_NAME}' (role: ${NODE_ROLE}) to version '${TARGET_VERSION}'..."

echo "==> [1/5] Upgrading kubeadm package..."
sudo apt-mark unhold kubeadm
sudo apt-get update
sudo apt-get install -y --allow-change-held-packages kubeadm="${TARGET_VERSION}"
sudo apt-mark hold kubeadm

if [[ "${NODE_ROLE}" == "control-plane" ]]; then
  echo "==> [2/5] Running kubeadm upgrade on control plane..."
  # Clean target version (strip package suffix like -1.1 if present)
  CLEAN_VERSION=$(echo "${TARGET_VERSION}" | cut -d'-' -f1)
  sudo kubeadm upgrade apply "v${CLEAN_VERSION}" -y || sudo kubeadm upgrade node
else
  echo "==> [2/5] Running kubeadm upgrade on worker node..."
  sudo kubeadm upgrade node
fi

echo "==> [3/5] Draining node workloads..."
echo "Please run on an active control plane with kubectl:"
echo "  kubectl drain ${NODE_NAME} --ignore-daemonsets --delete-emptydir-data --force"
read -rp "Press Enter once the node is drained, or to continue..."

echo "==> [4/5] Upgrading kubelet and kubectl..."
sudo apt-mark unhold kubelet kubectl
sudo apt-get install -y --allow-change-held-packages kubelet="${TARGET_VERSION}" kubectl="${TARGET_VERSION}"
sudo apt-mark hold kubelet kubectl

echo "==> Restarting kubelet..."
sudo systemctl daemon-reload
sudo systemctl restart kubelet

echo "==> [5/5] Node upgrade complete! Uncordon the node from a control plane:"
echo "  kubectl uncordon ${NODE_NAME}"
echo "===> Status for ${NODE_NAME}:"
sudo systemctl status kubelet --no-pager | head -n 10
