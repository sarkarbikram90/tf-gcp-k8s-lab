#!/usr/bin/env bash
# ==============================================================================
# Script: 02-init-control-plane.sh
# Purpose: Initializes the single Control Plane node and installs Flannel CNI
# Target: Run ONLY on the Control Plane node (k8s-lab-control-plane)
# ==============================================================================

set -euo pipefail

POD_CIDR="10.244.0.0/16"
CONTROL_PLANE_IP=$(hostname -I | awk '{print $1}')

echo "==> [1/4] Initializing Kubernetes Control Plane..."
echo "    Advertise Address: ${CONTROL_PLANE_IP}"
echo "    Pod Network CIDR:  ${POD_CIDR}"

sudo kubeadm init \
  --apiserver-advertise-address="${CONTROL_PLANE_IP}" \
  --pod-network-cidr="${POD_CIDR}" \
  --node-name="$(hostname -s)" | tee kubeadm-init.log

echo "==> [2/4] Setting up kubectl config for user ${USER}..."
mkdir -p "$HOME/.kube"
sudo cp -i /etc/kubernetes/admin.conf "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"

echo "==> [3/4] Installing Flannel CNI..."
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

echo "==> [4/4] Extracting worker join command..."
JOIN_CMD=$(kubeadm token create --print-join-command)
echo "------------------------------------------------------------------------"
echo "JOIN COMMAND FOR WORKER NODES:"
echo "sudo ${JOIN_CMD}"
echo "------------------------------------------------------------------------"

echo "sudo ${JOIN_CMD}" > "$HOME/join-worker.sh"
chmod +x "$HOME/join-worker.sh"
echo "Saved join command to $HOME/join-worker.sh"

echo "Checking cluster status..."
kubectl get nodes
echo "Run 'kubectl get pods -A -w' until CoreDNS pods are in 'Running' state."
