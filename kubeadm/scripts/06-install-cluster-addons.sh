#!/usr/bin/env bash
# ==============================================================================
# Script: 06-install-cluster-addons.sh
# Purpose: Bridges bare-metal / self-managed kubeadm (Levels 1-3) to stateful
#          and platform workloads (Barnacles 10Gi PVCs, Level 5 vLLM Model Cache,
#          Level 6 Golden Path Ingress/Gateway API, and optional Cilium eBPF).
#
# Usage:
#   ./kubeadm/scripts/06-install-cluster-addons.sh [--with-cilium-ebpf] [--with-gateway-api]
# ==============================================================================

set -euo pipefail

WITH_CILIUM=false
WITH_GATEWAY_API=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-cilium-ebpf)
      WITH_CILIUM=true
      shift
      ;;
    --with-gateway-api)
      WITH_GATEWAY_API=true
      shift
      ;;
    *)
      echo "[ERROR] Unknown flag: $1" >&2
      echo "Usage: $0 [--with-cilium-ebpf] [--with-gateway-api]" >&2
      exit 1
      ;;
  esac
done

echo "=============================================================================="
echo " Bootstrapping Self-Managed Kubernetes Platform Add-Ons"
echo "=============================================================================="

# 1. Dynamic StorageClass Provisioner (local-path-provisioner)
# Required on self-managed kubeadm clusters so Barnacles StatefulSet (10Gi PVCs)
# and Level 5 vLLM HuggingFace model weight caches bind automatically.
echo "[1/4] Installing Dynamic PersistentVolume Provisioner (local-path-storage)..."
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.28/deploy/local-path-storage.yaml
kubectl patch storageclass local-path \
  -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# 2. NGINX Ingress Controller (Bare-Metal / NodePort Mode for Internal GCP LB / IAP)
echo "[2/4] Installing NGINX Ingress Controller (ingress-nginx)..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.2/deploy/static/provider/baremetal/deploy.yaml

# Ensure ingress-nginx namespace carries the standard Kubernetes metadata label for NetworkPolicies
kubectl label namespace ingress-nginx kubernetes.io/metadata.name=ingress-nginx --overwrite

# 3. Kubernetes Gateway API Standard CRDs (GatewayClass, Gateway, HTTPRoute)
if [[ "${WITH_GATEWAY_API}" == "true" ]]; then
  echo "[3/4] Installing Kubernetes Gateway API v1.1.0 Standard CRDs..."
  kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.1.0/standard-install.yaml
fi

# 4. Optional Cilium eBPF CNI Upgrade (kube-proxy replacement + WireGuard mTLS)
if [[ "${WITH_CILIUM}" == "true" ]]; then
  echo "[4/4] Installing Cilium CLI & eBPF CNI with WireGuard node-to-node encryption..."
  CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
  CLI_ARCH=amd64
  curl -L --fail --remote-name-all "https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz"
  sudo tar xzvfC "cilium-linux-${CLI_ARCH}.tar.gz" /usr/local/bin
  rm -f "cilium-linux-${CLI_ARCH}.tar.gz"

  cilium install \
    --version 1.16.1 \
    --set kubeProxyReplacement=true \
    --set encryption.enabled=true \
    --set encryption.type=wireguard \
    --set hubble.relay.enabled=true \
    --set hubble.ui.enabled=true
else
  echo "[4/4] Skipping Cilium eBPF upgrade (pass --with-cilium-ebpf to enable eBPF + WireGuard)."
fi

echo "------------------------------------------------------------------------------"
echo " Platform Add-Ons Ready:"
echo "  • Default StorageClass : local-path (Ready for Barnacles & vLLM PVCs)"
echo "  • Ingress Controller   : ingress-nginx"
echo "  • Gateway API CRDs     : installed (HTTPRoute / Gateway)"
echo "  • Cilium eBPF + mTLS   : ${WITH_CILIUM}"
echo "=============================================================================="
