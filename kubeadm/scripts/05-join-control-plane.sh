#!/usr/bin/env bash
# ==============================================================================
# Script: 05-join-control-plane.sh
# Purpose: Helper script for secondary control planes to join the HA cluster
# Target: Run on secondary control planes (e.g. k8s-ha-cp-02, k8s-ha-cp-03)
# ==============================================================================

set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Usage: sudo $0 <JOIN_COMMAND_ARGUMENTS>"
  echo "Example:"
  echo "  sudo $0 kubeadm join 10.10.0.100:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash> --control-plane --certificate-key <key>"
  exit 1
fi

echo "==> Joining as Control Plane node with hostname $(hostname -s)..."
sudo "$@" --node-name="$(hostname -s)"

echo "==> Setting up kubectl configuration on this control plane node..."
mkdir -p "$HOME/.kube"
sudo cp -i /etc/kubernetes/admin.conf "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"

echo "===> Control plane node joined successfully! Check status with 'kubectl get nodes'."
