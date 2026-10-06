#!/usr/bin/env bash
# ==============================================================================
# Script: 03-join-worker.sh
# Purpose: Helper script to join a worker node to the Kubernetes cluster
# Target: Run on Worker nodes (k8s-lab-worker-01, k8s-lab-worker-02)
# ==============================================================================

set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Usage: sudo $0 <JOIN_COMMAND_ARGUMENTS>"
  echo "Example:"
  echo "  sudo $0 kubeadm join 10.10.0.2:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>"
  exit 1
fi

echo "==> Joining cluster with node name $(hostname -s)..."
sudo "$@" --node-name="$(hostname -s)"

echo "===> Successfully joined! Check 'kubectl get nodes' on the Control Plane node."
