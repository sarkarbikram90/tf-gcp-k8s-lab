#!/usr/bin/env bash
# ==============================================================================
# Script: 01-install-prereqs.sh
# Purpose: Prepares an Ubuntu 24.04 VM for Kubernetes (containerd, sysctl, kubeadm)
# Target: Run on ALL nodes (Control Plane and Workers)
# ==============================================================================

set -euo pipefail

echo "==> [1/6] Disabling swap..."
sudo swapoff -a
sudo sed -i '/swap/d' /etc/fstab

echo "==> [2/6] Configuring kernel modules for container runtime & Kubernetes..."
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

echo "==> [3/6] Setting required sysctl networking parameters..."
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system

echo "==> [4/6] Installing and configuring containerd runtime..."
sudo apt-get update -y
sudo apt-get install -y ca-certificates curl gnupg lsb-release

# Install containerd
sudo apt-get install -y containerd

# Configure containerd with SystemdCgroup = true
sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd

echo "==> [5/6] Adding official Kubernetes apt repository (pkgs.k8s.io)..."
K8S_VERSION="v1.31"
sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL "https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/deb/Release.key" | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg --yes

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list

echo "==> [6/6] Installing kubelet, kubeadm, and kubectl..."
sudo apt-get update -y
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

sudo systemctl enable --now kubelet

echo "===> Kubernetes prerequisites installation complete on $(hostname)!"
