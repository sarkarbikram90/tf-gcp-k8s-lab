#!/usr/bin/env bash
# ==============================================================================
# Script: verify-platform-policies.sh
# Purpose: Shift-Left CI & Local Policy-as-Code Verifier for Level 6/7 IDP.
#          Compiles all Kustomize Golden Paths, Barnacles, and Tenant Overlays
#          (`kubernetes/apps/*`) and verifies compliance against Kyverno
#          admission guardrails, Restricted PSS, and SRE Golden Signals.
#
# Usage:
#   ./scripts/platform/verify-platform-policies.sh
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

PASS_COUNT=0
FAIL_COUNT=0

log_ok()   { echo -e "\033[1;32m[PASS]\033[0m $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
log_fail() { echo -e "\033[1;31m[FAIL]\033[0m $*" >&2; FAIL_COUNT=$((FAIL_COUNT + 1)); }
log_info() { echo -e "\033[1;34m[INFO]\033[0m $*"; }

echo "=============================================================================="
echo " Shift-Left IDP Policy-as-Code & Golden Path Verification"
echo "=============================================================================="

# 1. Verify Core Platform Kustomize Overlays Build Cleanly
for base_dir in \
  "kubernetes/platform-barnacles" \
  "kubernetes/golden-paths/web-service" \
  "kubernetes/golden-paths/ai-agent-service"; do
  if kubectl kustomize "${REPO_ROOT}/${base_dir}" > "${TMP_DIR}/$(basename "${base_dir}").yaml"; then
    log_ok "Compiled base Kustomize overlay: ${base_dir}"
  else
    log_fail "Failed to compile Kustomize overlay: ${base_dir}"
  fi
done

# 2. Verify Every Tenant Application Under kubernetes/apps/*
for app_dir in "${REPO_ROOT}"/kubernetes/apps/*/; do
  [[ -d "${app_dir}" ]] || continue
  app_name="$(basename "${app_dir}")"
  rendered_file="${TMP_DIR}/app-${app_name}.yaml"

  log_info "Auditing tenant application: ${app_name} (${app_dir#"${REPO_ROOT}/"})"

  if ! kubectl kustomize "${app_dir}" > "${rendered_file}"; then
    log_fail "${app_name}: 'kubectl kustomize' build failed"
    continue
  fi
  log_ok "${app_name}: Kustomize overlay compiled cleanly"

  # Rule A: Disallow mutable ':latest' image tags (Kyverno: disallow-latest-image-tag)
  if grep -E "image:[[:space:]]*[^[:space:]]+:latest([[:space:]]|$)" "${rendered_file}" >/dev/null 2>&1; then
    log_fail "${app_name}: Uses prohibited mutable ':latest' container image tag"
  else
    log_ok "${app_name}: Immutable container image tag verified"
  fi

  # Rule B: Require FinOps & On-Call ownership label (Kyverno: require-owner-team-label)
  if grep -E "idp\.k8s-lab\.internal/owner-team:[[:space:]]*[a-z0-9-]+" "${rendered_file}" >/dev/null 2>&1; then
    log_ok "${app_name}: FinOps label 'idp.k8s-lab.internal/owner-team' present"
  else
    log_fail "${app_name}: Missing mandatory label 'idp.k8s-lab.internal/owner-team'"
  fi

  # Rule C: Enforce Restricted Pod Security Standards (runAsNonRoot, readOnlyRootFilesystem, allowPrivilegeEscalation: false)
  if grep -q "runAsNonRoot: true" "${rendered_file}" && \
     grep -q "readOnlyRootFilesystem: true" "${rendered_file}" && \
     grep -q "allowPrivilegeEscalation: false" "${rendered_file}"; then
    log_ok "${app_name}: Restricted Pod Security Standards (non-root, RO rootfs, no priv-esc) enforced"
  else
    log_fail "${app_name}: Missing Restricted Pod Security Standard fields"
  fi

  # Rule D: Require Zero-Trust NetworkPolicy, PodDisruptionBudget & HorizontalPodAutoscaler
  for required_kind in "NetworkPolicy" "PodDisruptionBudget" "HorizontalPodAutoscaler"; do
    if grep -E "^kind:[[:space:]]*${required_kind}$" "${rendered_file}" >/dev/null 2>&1; then
      log_ok "${app_name}: Required SRE/Zero-Trust resource '${required_kind}' present"
    else
      log_fail "${app_name}: Missing required resource '${required_kind}'"
    fi
  done

  # Rule E: Optional Kyverno CLI Evaluation (if kyverno binary is installed in CI/local)
  if command -v kyverno >/dev/null 2>&1; then
    if kyverno apply "${REPO_ROOT}/kubernetes/platform-idp/kyverno/03-validate-workload-hygiene.yaml" \
      --resource "${rendered_file}" >/dev/null 2>&1; then
      log_ok "${app_name}: Passed 'kyverno apply' validation policy evaluation"
    else
      log_fail "${app_name}: Failed 'kyverno apply' validation policy evaluation"
    fi
  fi
done

# 3. Verify CKS Supply-Chain, Quarantine & Observability Platform Manifests
for platform_manifest in \
  "kubernetes/platform-idp/kyverno/04-verify-image-signatures.yaml" \
  "kubernetes/security/network-policies/cks-pod-quarantine-policy.yaml" \
  "kubernetes/observability/04-alertmanager-sre-copilot-webhook.yaml" \
  "kubernetes/observability/05-grafana-dashboards-configmap.yaml"; do
  if [[ -s "${REPO_ROOT}/${platform_manifest}" ]] && grep -q "^apiVersion:" "${REPO_ROOT}/${platform_manifest}"; then
    log_ok "Verified platform security/observability manifest: ${platform_manifest}"
  else
    log_fail "Missing or invalid platform manifest: ${platform_manifest}"
  fi
done

echo "------------------------------------------------------------------------------"
echo " Verification Summary: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"
echo "=============================================================================="

if [[ "${FAIL_COUNT}" -gt 0 ]]; then
  exit 1
fi
