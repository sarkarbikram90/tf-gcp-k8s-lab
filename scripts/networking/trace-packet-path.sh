#!/usr/bin/env bash
# ==============================================================================
# trace-packet-path.sh — End-to-End Kubernetes & Linux Network Path Inspector
# ==============================================================================
# Inspects the live networking layers of a Kubernetes workload in net-lab:
#   1. Pod & Node placement + IP / Subnet allocation
#   2. ClusterIP vs. Headless DNS resolution via CoreDNS
#   3. EndpointSlices backing the Service
#   4. Host Linux routing table, CNI bridge, and kube-proxy iptables chains
# ==============================================================================
set -euo pipefail

NAMESPACE="${1:-net-lab}"
SERVICE="${2:-echo-clusterip-svc}"
HEADLESS_SVC="${3:-echo-headless-svc}"

echo "======================================================================"
echo " 1. POD PLACEMENT & IP ALLOCATION (Namespace: ${NAMESPACE})"
echo "======================================================================"
kubectl get pods -n "${NAMESPACE}" -o wide

echo ""
echo "======================================================================"
echo " 2. SERVICE VIPs & ENDPOINTSLICES"
echo "======================================================================"
kubectl get svc -n "${NAMESPACE}" -o wide
echo ""
kubectl get endpointslices -n "${NAMESPACE}" -o wide

DIAG_POD=$(kubectl get pods -n "${NAMESPACE}" -l app=net-diag-agent -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [[ -n "${DIAG_POD}" ]]; then
  echo ""
  echo "======================================================================"
  echo " 3. COREDNS RESOLUTION: CLUSTERIP VIP vs. HEADLESS POD A-RECORDS"
  echo "======================================================================"
  echo "--- /etc/resolv.conf inside ${DIAG_POD} ---"
  kubectl exec -n "${NAMESPACE}" "${DIAG_POD}" -- cat /etc/resolv.conf
  echo ""
  echo "--- nslookup ${SERVICE}.${NAMESPACE}.svc.cluster.local (ClusterIP VIP) ---"
  kubectl exec -n "${NAMESPACE}" "${DIAG_POD}" -- nslookup "${SERVICE}.${NAMESPACE}.svc.cluster.local" || true
  echo ""
  echo "--- nslookup ${HEADLESS_SVC}.${NAMESPACE}.svc.cluster.local (Headless Pod IPs) ---"
  kubectl exec -n "${NAMESPACE}" "${DIAG_POD}" -- nslookup "${HEADLESS_SVC}.${NAMESPACE}.svc.cluster.local" || true

  echo ""
  echo "======================================================================"
  echo " 4. EAST-WEST HTTP LOAD BALANCING ACROSS POD REPLICAS"
  echo "======================================================================"
  for i in 1 2 3 4; do
    printf "Request #%d -> " "${i}"
    kubectl exec -n "${NAMESPACE}" "${DIAG_POD}" -- wget -qO- -T 3 "http://${SERVICE}.${NAMESPACE}.svc.cluster.local/" || true
  done
fi

echo ""
echo "======================================================================"
echo " 5. LOCAL NODE LINUX NETWORKING & KUBE-PROXY IPTABLES"
echo "======================================================================"
echo "--- Host Interfaces & MTU ---"
ip -br link show || true
echo ""
echo "--- Host Routing Table (Pod CIDRs & VXLAN / CNI routes) ---"
ip route show || true
echo ""
CLUSTER_IP=$(kubectl get svc -n "${NAMESPACE}" "${SERVICE}" -o jsonpath='{.spec.clusterIP}' 2>/dev/null || true)
if [[ -n "${CLUSTER_IP}" && "${CLUSTER_IP}" != "None" ]] && command -v iptables-save >/dev/null 2>&1; then
  echo "--- kube-proxy iptables rules matching Service ClusterIP (${CLUSTER_IP}) ---"
  sudo iptables-save | grep "${CLUSTER_IP}" || true
fi
