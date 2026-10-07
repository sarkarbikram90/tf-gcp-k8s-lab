#!/usr/bin/env bash
# ==============================================================================
# Script: 04-init-ha-control-plane.sh
# Purpose: Initializes the PRIMARY Control Plane node in an HA topology
# Target: Run ONLY on the primary control plane (e.g. k8s-ha-cp-01)
# ==============================================================================

set -euo pipefail

ENDPOINT="${1:-10.10.0.100:6443}"
POD_CIDR="10.244.0.0/16"

echo "==> [1/5] Initializing Primary Control Plane in HA Mode..."
echo "    Control Plane Endpoint: ${ENDPOINT}"
echo "    Pod CIDR:               ${POD_CIDR}"

# Initialize with --upload-certs to allow secondary control planes to pull certificates securely
sudo kubeadm init \
  --control-plane-endpoint="${ENDPOINT}" \
  --upload-certs \
  --pod-network-cidr="${POD_CIDR}" \
  --node-name="$(hostname -s)" | tee kubeadm-ha-init.log

echo "==> [2/5] Configuring kubectl for user ${USER}..."
mkdir -p "$HOME/.kube"
sudo cp -i /etc/kubernetes/admin.conf "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"

echo "==> [3/5] Installing Flannel CNI..."
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

echo "==> [4/5] Extracting join commands..."
# Certificate key expires in 2 hours by default
CERT_KEY=$(sudo kubeadm init phase upload-certs --upload-certs | tail -n 1)
TOKEN=$(sudo kubeadm token create)
CA_HASH=$(openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //')

CP_JOIN_CMD="kubeadm join ${ENDPOINT} --token ${TOKEN} --discovery-token-ca-cert-hash sha256:${CA_HASH} --control-plane --certificate-key ${CERT_KEY}"
WORKER_JOIN_CMD="kubeadm join ${ENDPOINT} --token ${TOKEN} --discovery-token-ca-cert-hash sha256:${CA_HASH}"

echo "------------------------------------------------------------------------"
echo "SECONDARY CONTROL PLANE JOIN COMMAND (Run on cp-02 and cp-03):"
echo "sudo ${CP_JOIN_CMD}"
echo "------------------------------------------------------------------------"
echo "WORKER JOIN COMMAND (Run on worker-01, worker-02, and worker-03):"
echo "sudo ${WORKER_JOIN_CMD}"
echo "------------------------------------------------------------------------"

echo "sudo ${CP_JOIN_CMD}" > "$HOME/join-control-plane.sh"
echo "sudo ${WORKER_JOIN_CMD}" > "$HOME/join-worker.sh"
chmod +x "$HOME/join-control-plane.sh" "$HOME/join-worker.sh"

echo "==> [5/5] Current cluster status:"
kubectl get nodes
echo "Note: The certificate key is valid for 2 hours. Secondary control planes should join within that window."
