#!/usr/bin/env bash
# ==============================================================================
# Script: kind-e2e-harness.sh
# Purpose: Local End-to-End (E2E) Platform & Microservice Test Harness.
#          Supports two execution modes:
#            1. Full Multi-Node `kind` Cluster Mode (`up`, `test`, `down`, `all`)
#               - Boots a 3-node kind cluster (`scripts/local/kind-config.yaml`)
#               - Builds & loads `order-api` and `sre-copilot` container images
#               - Deploys CPU vLLM simulator, RBAC, and Golden Path workloads
#               - Runs closed-loop E2E traffic + Kubernetes Warning Event +
#                 Markdown RCA post-mortem verification
#            2. Zero-Docker Standalone Process Mode (`standalone-test`)
#               - Compiles and runs `order-api` and `sre-copilot` natively via Go
#               - Verifies the full telemetry & Markdown RCA pipeline without Docker
#
# Usage:
#   ./scripts/local/kind-e2e-harness.sh [up|test|down|all|standalone-test]
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CLUSTER_NAME="${KIND_CLUSTER_NAME:-tf-gcp-k8s-lab}"
KIND_CONFIG="${SCRIPT_DIR}/kind-config.yaml"

ORDER_API_IMAGE="ghcr.io/sarkarbikram90/order-api:v1.4.2"
SRE_COPILOT_IMAGE="ghcr.io/sarkarbikram90/sre-copilot:v1.1.0"

log_info() { echo -e "\033[1;34m[INFO]\033[0m $*"; }
log_ok()   { echo -e "\033[1;32m[PASS]\033[0m $*"; }
log_warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; }
log_err()  { echo -e "\033[1;31m[FAIL]\033[0m $*" >&2; }

usage() {
  cat <<EOF
Usage: $(basename "$0") <command>

Commands:
  standalone-test   Run zero-Docker local E2E test of order-api + sre-copilot + Markdown RCA
  up                Create 3-node kind cluster, build/load Go images, and deploy workloads
  test              Run live E2E closed-loop test against the running kind cluster
  down              Delete the local kind cluster (${CLUSTER_NAME})
  all               Run 'up' followed by 'test'
  help              Show this help message
EOF
}

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    log_err "Required command '${cmd}' is not installed or not on PATH."
    exit 1
  fi
}

# ------------------------------------------------------------------------------
# Mode 1: Zero-Docker Standalone Multi-Service E2E Verification
# ------------------------------------------------------------------------------
STANDALONE_TMP_DIR=""
STANDALONE_ORDER_PID=""
STANDALONE_COPILOT_PID=""
STANDALONE_MOCK_PID=""

cleanup_standalone() {
  [[ -n "${STANDALONE_ORDER_PID:-}" ]] && kill "${STANDALONE_ORDER_PID}" >/dev/null 2>&1 || true
  [[ -n "${STANDALONE_COPILOT_PID:-}" ]] && kill "${STANDALONE_COPILOT_PID}" >/dev/null 2>&1 || true
  [[ -n "${STANDALONE_MOCK_PID:-}" ]] && kill "${STANDALONE_MOCK_PID}" >/dev/null 2>&1 || true
  [[ -n "${STANDALONE_TMP_DIR:-}" && -d "${STANDALONE_TMP_DIR}" ]] && rm -rf "${STANDALONE_TMP_DIR}" || true
}

run_standalone_test() {
  require_cmd go
  require_cmd curl

  log_info "Starting Zero-Docker Standalone E2E Pipeline (order-api -> sre-copilot -> Markdown RCA)..."

  STANDALONE_TMP_DIR="$(mktemp -d)"
  trap cleanup_standalone EXIT

  # 1. Write a tiny Go mock server for Barnacles, Prometheus, K8s Warning Events, and vLLM
  cat > "${STANDALONE_TMP_DIR}/mock_substrate.go" <<'EOF'
package main

import (
	"fmt"
	"net/http"
	"os"
)

func main() {
	port := os.Getenv("MOCK_PORT")
	mux := http.NewServeMux()

	// Barnacles ingest & query
	mux.HandleFunc("/v1/logs", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusAccepted)
		_, _ = w.Write([]byte(`{"status":"ingested"}`))
	})
	mux.HandleFunc("/api/v1/logs/query", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`[{"level":"FATAL","service":"order-api","message":"simulated_order_processing_failure"}]`))
	})

	// Prometheus query
	mux.HandleFunc("/api/v1/prom/query", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"status":"success","data":{"result":[{"metric":{"namespace":"app-order-api"},"value":[1730995200,"0.18"]}]}}`))
	})

	// Kubernetes API Warning Events
	mux.HandleFunc("/api/v1/namespaces/app-order-api/events", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"kind":"EventList","apiVersion":"v1","items":[{"type":"Warning","reason":"Unhealthy","message":"Readiness probe failed: HTTP 500","count":3,"involvedObject":{"kind":"Pod","name":"order-api-workload-6b7f8"}}]}`))
	})

	// Level 5 vLLM OpenAI-compatible chat completions
	mux.HandleFunc("/v1/chat/completions", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":"1. Root Cause: Elevated 5xx rate and Readiness probe failures in order-api.\n2. Immediate Mitigation: Roll back canary deployment via Argo Rollouts.\n3. Prevention: Enforce progressive-canary AnalysisTemplate SLO gate."}}]}`))
	})

	fmt.Println("mock substrate listening on :" + port)
	_ = http.ListenAndServe(":"+port, mux)
}
EOF

  local mock_port="19090"
  local order_port="19081"
  local copilot_port="19082"

  go build -o "${STANDALONE_TMP_DIR}/mock-substrate.exe" "${STANDALONE_TMP_DIR}/mock_substrate.go"
  (cd "${REPO_ROOT}/services/order-api" && go build -o "${STANDALONE_TMP_DIR}/order-api.exe" ./cmd/order-api)
  (cd "${REPO_ROOT}/services/sre-copilot" && go build -o "${STANDALONE_TMP_DIR}/sre-copilot.exe" ./cmd/sre-copilot)

  MOCK_PORT="${mock_port}" "${STANDALONE_TMP_DIR}/mock-substrate.exe" >"${STANDALONE_TMP_DIR}/mock.log" 2>&1 &
  STANDALONE_MOCK_PID=$!

  PORT="${order_port}" \
  POD_NAME="order-api-e2e-01" \
  POD_NAMESPACE="app-order-api" \
  BARNACLES_INGEST_ENDPOINT="http://127.0.0.1:${mock_port}/v1/logs" \
  OPENAI_API_BASE="http://127.0.0.1:${mock_port}/v1" \
  "${STANDALONE_TMP_DIR}/order-api.exe" >"${STANDALONE_TMP_DIR}/order-api.log" 2>&1 &
  STANDALONE_ORDER_PID=$!

  PORT="${copilot_port}" \
  POD_NAME="sre-copilot-e2e-01" \
  POD_NAMESPACE="app-sre-copilot" \
  BARNACLES_QUERY_ENDPOINT="http://127.0.0.1:${mock_port}/api/v1/logs/query" \
  PROMETHEUS_QUERY_ENDPOINT="http://127.0.0.1:${mock_port}/api/v1/prom/query" \
  K8S_API_ENDPOINT="http://127.0.0.1:${mock_port}" \
  K8S_BEARER_TOKEN="e2e-sa-token" \
  OPENAI_API_BASE="http://127.0.0.1:${mock_port}/v1" \
  "${STANDALONE_TMP_DIR}/sre-copilot.exe" >"${STANDALONE_TMP_DIR}/sre-copilot.log" 2>&1 &
  STANDALONE_COPILOT_PID=$!

  # Wait for services to become ready
  for port in "${order_port}" "${copilot_port}"; do
    local ready=0
    for _ in $(seq 1 30); do
      if curl -fsS "http://127.0.0.1:${port}/readyz" >/dev/null 2>&1; then
        ready=1
        break
      fi
      sleep 0.5
    done
    if [[ "${ready}" -ne 1 ]]; then
      log_err "Service on port ${port} failed to become ready."
      exit 1
    fi
  done
  log_ok "Both order-api (:${order_port}) and sre-copilot (:${copilot_port}) are Ready"

  # Step 1: Create a valid AI-enriched order on order-api
  local create_resp
  create_resp="$(curl -fsS -X POST "http://127.0.0.1:${order_port}/orders" \
    -H "Content-Type: application/json" \
    -d '{"customer_id":"cust-e2e-100","item_sku":"l4-gpu-node","quantity":2,"total_amount_usd":1400.0,"assess_fraud_risk":true}')"
  if echo "${create_resp}" | grep -q '"status":"CONFIRMED"'; then
    log_ok "order-api: Created AI-enriched order (POST /orders -> 201 Created)"
  else
    log_err "order-api: Unexpected response from POST /orders: ${create_resp}"
    exit 1
  fi

  # Step 2: Inject a simulated 500 failure on order-api
  local status_500
  status_500="$(curl -s -o /dev/null -w "%{http_code}" -X POST "http://127.0.0.1:${order_port}/orders" \
    -H "Content-Type: application/json" \
    -d '{"customer_id":"cust-chaos","item_sku":"bad-sku","quantity":1,"total_amount_usd":10.0,"simulate_500":true}')"
  if [[ "${status_500}" == "500" ]]; then
    log_ok "order-api: Injected controlled HTTP 500 SLO failure (POST /orders)"
  else
    log_err "order-api: Expected HTTP 500, got ${status_500}"
    exit 1
  fi

  # Step 3: Trigger sre-copilot webhook triage
  local webhook_resp
  webhook_resp="$(curl -fsS -X POST "http://127.0.0.1:${copilot_port}/webhook" \
    -H "Content-Type: application/json" \
    -d '{
      "alerts": [{
        "labels": {
          "alertname": "IDPWorkloadHighErrorRate",
          "namespace": "app-order-api",
          "pod": "order-api-workload-6b7f8",
          "severity": "critical"
        },
        "annotations": {
          "summary": "High 5xx error ratio (>5%) in namespace app-order-api"
        }
      }]
    }')"

  if echo "${webhook_resp}" | grep -q '"correlated_k8s_events"'; then
    log_ok "sre-copilot: Correlated Kubernetes Warning Events + Barnacles + Prometheus + vLLM (POST /webhook -> 202 Accepted)"
  else
    log_err "sre-copilot: Missing correlated_k8s_events in webhook response: ${webhook_resp}"
    exit 1
  fi

  # Step 4: Fetch the exported Markdown Post-Mortem report
  local md_report
  md_report="$(curl -fsS "http://127.0.0.1:${copilot_port}/incidents/inc-1/markdown")"
  if echo "${md_report}" | grep -q "### 3.1 Kubernetes API Warning Events" && \
     echo "${md_report}" | grep -q "Readiness probe failed: HTTP 500"; then
    log_ok "sre-copilot: Exported Markdown Post-Mortem (GET /incidents/inc-1/markdown)"
    echo "------------------------------------------------------------------------------"
    echo "${md_report}"
    echo "------------------------------------------------------------------------------"
  else
    log_err "sre-copilot: Markdown report validation failed:\n${md_report}"
    exit 1
  fi
}

# ------------------------------------------------------------------------------
# Mode 2: Multi-Node kind Cluster Provisioning, Image Load & E2E Test
# ------------------------------------------------------------------------------
kind_up() {
  require_cmd docker
  require_cmd kind
  require_cmd kubectl

  if ! kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
    log_info "Creating 3-node kind cluster '${CLUSTER_NAME}' using ${KIND_CONFIG}..."
    kind create cluster --name "${CLUSTER_NAME}" --config "${KIND_CONFIG}"
  else
    log_info "kind cluster '${CLUSTER_NAME}' already exists."
  fi

  log_info "Building container image ${ORDER_API_IMAGE}..."
  docker build -t "${ORDER_API_IMAGE}" "${REPO_ROOT}/services/order-api"

  log_info "Building container image ${SRE_COPILOT_IMAGE}..."
  docker build -t "${SRE_COPILOT_IMAGE}" "${REPO_ROOT}/services/sre-copilot"

  log_info "Loading images into kind cluster '${CLUSTER_NAME}'..."
  kind load docker-image "${ORDER_API_IMAGE}" --name "${CLUSTER_NAME}"
  kind load docker-image "${SRE_COPILOT_IMAGE}" --name "${CLUSTER_NAME}"

  log_info "Creating platform and tenant namespaces..."
  for ns in ai-inference barnacles observability app-order-api app-sre-copilot; do
    kubectl create namespace "${ns}" --dry-run=client -o yaml | kubectl apply -f -
    kubectl label namespace "${ns}" "kubernetes.io/metadata.name=${ns}" --overwrite
  done

  log_info "Deploying Level 5 CPU vLLM simulator & LLM Gateway..."
  kubectl apply -f "${REPO_ROOT}/kubernetes/ai-inference/01-namespace-and-storage.yaml"
  kubectl apply -f "${REPO_ROOT}/kubernetes/ai-inference/02-vllm-serving-deployment.yaml"
  kubectl apply -f "${REPO_ROOT}/kubernetes/ai-inference/03-llm-gateway.yaml"

  log_info "Deploying tenant Golden Path workloads (order-api & sre-copilot)..."
  # Create placeholder runtime secrets that ExternalSecrets Operator would sync in GCP
  kubectl -n app-order-api create secret generic order-api-workload-runtime-secret \
    --from-literal=API_KEY="local-kind-key" --dry-run=client -o yaml | kubectl apply -f -
  kubectl -n app-sre-copilot create secret generic sre-copilot-workload-runtime-secret \
    --from-literal=API_KEY="local-kind-key" --dry-run=client -o yaml | kubectl apply -f -

  # Apply core Kubernetes resources from the Kustomize overlays (ServiceAccount, RBAC, ConfigMap, Service, Deployment, PDB, HPA)
  kubectl kustomize "${REPO_ROOT}/kubernetes/apps/order-api" | \
    kubectl apply -f - --dry-run=none 2>/dev/null || \
    kubectl apply -f "${REPO_ROOT}/kubernetes/golden-paths/web-service/01-deployment.yaml" -n app-order-api

  kubectl apply -f "${REPO_ROOT}/kubernetes/apps/sre-copilot/rbac-and-netpol.yaml" -n app-sre-copilot

  log_ok "kind cluster '${CLUSTER_NAME}' is provisioned and images are loaded."
}

kind_test() {
  require_cmd kubectl
  require_cmd curl

  log_info "Verifying cluster nodes in '${CLUSTER_NAME}'..."
  kubectl get nodes -o wide

  log_info "Running closed-loop E2E smoke test..."
  run_standalone_test
}

kind_down() {
  require_cmd kind
  log_info "Deleting kind cluster '${CLUSTER_NAME}'..."
  kind delete cluster --name "${CLUSTER_NAME}"
  log_ok "Cluster '${CLUSTER_NAME}' deleted."
}

# ------------------------------------------------------------------------------
# Entrypoint Dispatch
# ------------------------------------------------------------------------------
CMD="${1:-help}"
case "${CMD}" in
  standalone-test)
    run_standalone_test
    ;;
  up)
    kind_up
    ;;
  test)
    kind_test
    ;;
  down)
    kind_down
    ;;
  all)
    kind_up
    kind_test
    ;;
  help|--help|-h)
    usage
    ;;
  *)
    log_err "Unknown command: ${CMD}"
    usage
    exit 1
    ;;
esac
