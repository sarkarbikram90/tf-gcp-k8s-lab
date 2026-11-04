#!/usr/bin/env bash
# ==============================================================================
# Internal Developer Platform (IDP) Self-Service Application Scaffolder
# Gives developers a 1-command CLI to scaffold a Golden Path workload in
# `kubernetes/apps/<app-name>` without writing raw Kubernetes boilerplate.
#
# Usage:
#   ./scripts/platform/scaffold-app.sh <app-name> [options]
#
# Options:
#   --type <web-service|ai-agent>   Golden Path blueprint (default: web-service)
#   --team <team-name>              Owning engineering team label (default: platform-devs)
#   --image <registry/repo:tag>     Container image (default: ghcr.io/sarkarbikram90/<app>:v1.0.0)
#   --port <number>                 Container HTTP port (default: 8080)
#   --min-replicas <number>         HPA minimum replicas (default: 2)
#   --max-replicas <number>         HPA maximum replicas (default: 6)
#   --with-secret                   Attach GCP Secret Manager ExternalSecret component
#   --with-storage                  Attach 10Gi PersistentVolumeClaim component
#   --force                         Overwrite existing app directory if present
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

usage() {
  cat <<EOF
Usage: $(basename "$0") <app-name> [options]

Scaffold a Golden Path application in kubernetes/apps/<app-name> for automatic
Argo CD GitOps onboarding and Kyverno zero-trust governance.

Options:
  --type <web-service|ai-agent>   Golden Path blueprint (default: web-service)
  --team <team-name>              Owning team label (default: platform-devs)
  --image <registry/repo:tag>     Container image (must not use :latest)
  --port <number>                 HTTP container port (default: 8080)
  --min-replicas <number>         HPA minimum replicas (default: 2)
  --max-replicas <number>         HPA maximum replicas (default: 6)
  --with-secret                   Include GCP Secret Manager ExternalSecret brick
  --with-storage                  Include 10Gi PersistentVolumeClaim brick
  --force                         Overwrite target directory if it already exists
  -h, --help                      Show this help message

Example:
  ./scripts/platform/scaffold-app.sh payment-gateway \\
    --type ai-agent \\
    --team checkout-squad \\
    --image ghcr.io/sarkarbikram90/payment-gateway:v1.1.0 \\
    --with-secret
EOF
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  usage
  exit 0
fi

APP_NAME="$1"
shift

# Defaults
BLUEPRINT_TYPE="web-service"
TEAM_NAME="platform-devs"
IMAGE=""
PORT="8080"
MIN_REPLICAS="2"
MAX_REPLICAS="6"
WITH_SECRET=false
WITH_STORAGE=false
FORCE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --type)
      BLUEPRINT_TYPE="$2"
      shift 2
      ;;
    --team)
      TEAM_NAME="$2"
      shift 2
      ;;
    --image)
      IMAGE="$2"
      shift 2
      ;;
    --port)
      PORT="$2"
      shift 2
      ;;
    --min-replicas)
      MIN_REPLICAS="$2"
      shift 2
      ;;
    --max-replicas)
      MAX_REPLICAS="$2"
      shift 2
      ;;
    --with-secret)
      WITH_SECRET=true
      shift
      ;;
    --with-storage)
      WITH_STORAGE=true
      shift
      ;;
    --force)
      FORCE=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[ERROR] Unknown flag: $1" >&2
      usage
      exit 1
      ;;
  esac
done

# 1. Validate DNS-1123 application name
if ! [[ "${APP_NAME}" =~ ^[a-z][a-z0-9-]{1,38}[a-z0-9]$ ]]; then
  echo "[ERROR] Invalid app-name '${APP_NAME}'. Must be lowercase DNS-1123 (3-40 chars, a-z, 0-9, hyphens)." >&2
  exit 1
fi

# 2. Validate Golden Path blueprint type
case "${BLUEPRINT_TYPE}" in
  web-service)
    GOLDEN_PATH_REL="../../golden-paths/web-service"
    ;;
  ai-agent|ai-agent-service)
    BLUEPRINT_TYPE="ai-agent-service"
    GOLDEN_PATH_REL="../../golden-paths/ai-agent-service"
    ;;
  *)
    echo "[ERROR] Unsupported --type '${BLUEPRINT_TYPE}'. Choose 'web-service' or 'ai-agent'." >&2
    exit 1
    ;;
esac

if [[ -z "${IMAGE}" ]]; then
  IMAGE="ghcr.io/sarkarbikram90/${APP_NAME}:v1.0.0"
fi

# 3. Shift-Left Kyverno Policy Pre-Check (Disallow mutable :latest tag)
if [[ "${IMAGE}" == *":latest" ]]; then
  echo "[POLICY BLOCKED] Image '${IMAGE}' uses a mutable ':latest' tag." >&2
  echo "                 Kyverno policy 'idp-validate-production-hygiene' requires an immutable version tag (e.g., :v1.0.0)." >&2
  exit 1
fi

APP_DIR="${REPO_ROOT}/kubernetes/apps/${APP_NAME}"
if [[ -d "${APP_DIR}" && "${FORCE}" != "true" ]]; then
  echo "[ERROR] Application directory already exists: ${APP_DIR}" >&2
  echo "        Pass --force to overwrite." >&2
  exit 1
fi

mkdir -p "${APP_DIR}"

# 4. Build Kustomize components block if optional bricks were requested
COMPONENTS_BLOCK=""
if [[ "${WITH_SECRET}" == "true" || "${WITH_STORAGE}" == "true" ]]; then
  COMPONENTS_BLOCK=$'\ncomponents:'
  if [[ "${WITH_SECRET}" == "true" ]]; then
    COMPONENTS_BLOCK="${COMPONENTS_BLOCK}"$'\n  - ../../golden-paths/components/external-secret'
  fi
  if [[ "${WITH_STORAGE}" == "true" ]]; then
    COMPONENTS_BLOCK="${COMPONENTS_BLOCK}"$'\n  - ../../golden-paths/components/persistent-storage'
  fi
fi

# 5. Write kustomization.yaml
cat > "${APP_DIR}/kustomization.yaml" <<EOF
# ==============================================================================
# Golden Path Application: ${APP_NAME}
# Generated by: scripts/platform/scaffold-app.sh
# Automatically synced by Argo CD ApplicationSet into namespace: app-${APP_NAME}
# ==============================================================================
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: app-${APP_NAME}
namePrefix: ${APP_NAME}-

labels:
  - includeSelectors: true
    pairs:
      app.kubernetes.io/name: ${APP_NAME}
  - includeSelectors: false
    pairs:
      idp.k8s-lab.internal/owner-team: ${TEAM_NAME}

resources:
  - ${GOLDEN_PATH_REL}
${COMPONENTS_BLOCK}

patches:
  - path: workload-patch.yaml
EOF

# 6. Write workload-patch.yaml
cat > "${APP_DIR}/workload-patch.yaml" <<EOF
# ==============================================================================
# Developer Workload Intent (${APP_NAME})
# ==============================================================================
apiVersion: apps/v1
kind: Deployment
metadata:
  name: workload
spec:
  template:
    spec:
      containers:
        - name: app
          image: ${IMAGE}
          ports:
            - name: http
              containerPort: ${PORT}
              protocol: TCP
          env:
            - name: APP_NAME
              value: "${APP_NAME}"
            - name: APP_ENV
              value: "production"
          resources:
            requests:
              cpu: 150m
              memory: 256Mi
            limits:
              cpu: 500m
              memory: 512Mi
---
apiVersion: v1
kind: Service
metadata:
  name: workload
spec:
  ports:
    - name: http
      port: ${PORT}
      targetPort: http
      protocol: TCP
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: workload
spec:
  minReplicas: ${MIN_REPLICAS}
  maxReplicas: ${MAX_REPLICAS}
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: workload
spec:
  rules:
    - host: ${APP_NAME}.k8s-lab.internal
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: workload
                port:
                  number: ${PORT}
EOF

if [[ "${WITH_SECRET}" == "true" ]]; then
  cat >> "${APP_DIR}/workload-patch.yaml" <<EOF
---
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: workload-secret
spec:
  dataFrom:
    - extract:
        key: gcp-sm-${APP_NAME}-production
EOF
fi

echo "=============================================================================="
echo " Golden Path Application Scaffolded: ${APP_NAME}"
echo "=============================================================================="
echo "  Directory      : kubernetes/apps/${APP_NAME}/"
echo "  Namespace      : app-${APP_NAME} (restricted PSS + Kyverno auto-guardrails)"
echo "  Blueprint      : ${BLUEPRINT_TYPE}"
echo "  Owner Team     : ${TEAM_NAME}"
echo "  Image          : ${IMAGE}"
echo "  Ingress Host   : https://${APP_NAME}.k8s-lab.internal"
echo "  Autoscaling    : ${MIN_REPLICAS} -> ${MAX_REPLICAS} replicas (PDB minAvailable: 1)"
echo "  Cloud Secret   : ${WITH_SECRET}"
echo "  Persistent PVC : ${WITH_STORAGE}"
echo "------------------------------------------------------------------------------"

if command -v kubectl >/dev/null 2>&1; then
  echo "[VERIFY] Compiling Golden Path overlay with 'kubectl kustomize'..."
  RENDERED_KINDS=$(kubectl kustomize "${APP_DIR}" | grep -E "^kind:" | awk '{print $2}' | sort | uniq -c)
  echo "${RENDERED_KINDS}"
  echo "------------------------------------------------------------------------------"
fi

cat <<EOF
Next Steps (GitOps Self-Service):
  1. Preview compiled manifests : kubectl kustomize kubernetes/apps/${APP_NAME}
  2. Commit & open Pull Request : git add kubernetes/apps/${APP_NAME} && git commit -m "feat(apps): onboard ${APP_NAME}"
  3. Add 'preview-env' PR label : Argo CD spins up namespace 'preview-pr-<id>' automatically
  4. Merge to main              : Argo CD deploys to 'app-${APP_NAME}' with zero manual kubectl commands
EOF
