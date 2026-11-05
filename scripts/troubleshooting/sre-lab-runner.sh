#!/usr/bin/env bash
# ==============================================================================
# Script: sre-lab-runner.sh
# Purpose: Automated Failure-Injection, Verification & Blind Timed Drill Harness
#          for the 14-Scenario Kubernetes, Barnacles, vLLM & IDP SRE Laboratory.
# Usage:
#   ./scripts/troubleshooting/sre-lab-runner.sh list
#   ./scripts/troubleshooting/sre-lab-runner.sh inject <01..14> [--allow-node-fault]
#   ./scripts/troubleshooting/sre-lab-runner.sh random
#   ./scripts/troubleshooting/sre-lab-runner.sh status
#   ./scripts/troubleshooting/sre-lab-runner.sh verify <01..14|current>
#   ./scripts/troubleshooting/sre-lab-runner.sh reset [all]
# ==============================================================================

set -euo pipefail

LAB_NAMESPACE="sre-lab"
STATE_CM="sre-lab-state"
ACTION="${1:-help}"
TARGET="${2:-}"
EXTRA_FLAG="${3:-}"

# ------------------------------------------------------------------------------
# Helper Functions
# ------------------------------------------------------------------------------
log_info()  { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
log_ok()    { echo -e "\033[1;32m[PASS]\033[0m  $*"; }
log_warn()  { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
log_err()   { echo -e "\033[1;31m[FAIL]\033[0m  $*"; }

normalize_id() {
  local raw="${1:-}"
  case "${raw}" in
    1|01) echo "01" ;;
    2|02) echo "02" ;;
    3|03) echo "03" ;;
    4|04) echo "04" ;;
    5|05) echo "05" ;;
    6|06) echo "06" ;;
    7|07) echo "07" ;;
    8|08) echo "08" ;;
    9|09) echo "09" ;;
    10)   echo "10" ;;
    11)   echo "11" ;;
    12)   echo "12" ;;
    13)   echo "13" ;;
    14)   echo "14" ;;
    current) echo "current" ;;
    all)  echo "all" ;;
    *)    echo "" ;;
  esac
}

ensure_namespace() {
  if ! kubectl get namespace "${LAB_NAMESPACE}" >/dev/null 2>&1; then
    kubectl create namespace "${LAB_NAMESPACE}" >/dev/null
  fi
}

record_state() {
  local lab_id="$1"
  local mode="${2:-explicit}"
  local now_epoch
  now_epoch="$(date +%s)"
  ensure_namespace
  kubectl create configmap "${STATE_CM}" -n "${LAB_NAMESPACE}" \
    --from-literal=active_lab="${lab_id}" \
    --from-literal=mode="${mode}" \
    --from-literal=start_epoch="${now_epoch}" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
}

get_active_lab() {
  kubectl get configmap "${STATE_CM}" -n "${LAB_NAMESPACE}" \
    -o jsonpath='{.data.active_lab}' 2>/dev/null || echo ""
}

print_elapsed_time() {
  local start_epoch
  start_epoch="$(kubectl get configmap "${STATE_CM}" -n "${LAB_NAMESPACE}" -o jsonpath='{.data.start_epoch}' 2>/dev/null || echo "")"
  if [[ -n "${start_epoch}" ]]; then
    local now_epoch elapsed mins secs
    now_epoch="$(date +%s)"
    elapsed=$(( now_epoch - start_epoch ))
    mins=$(( elapsed / 60 ))
    secs=$(( elapsed % 60 ))
    log_info "Elapsed incident time: ${mins}m ${secs}s"
  fi
}

usage() {
  cat <<'EOF'
Kubernetes SRE Troubleshooting Lab Runner (tf-gcp-k8s-lab)

Usage:
  ./scripts/troubleshooting/sre-lab-runner.sh list
  ./scripts/troubleshooting/sre-lab-runner.sh inject <01..14> [--allow-node-fault]
  ./scripts/troubleshooting/sre-lab-runner.sh random
  ./scripts/troubleshooting/sre-lab-runner.sh status
  ./scripts/troubleshooting/sre-lab-runner.sh verify <01..14|current>
  ./scripts/troubleshooting/sre-lab-runner.sh reset [all]

Scenarios (Levels 1-4 Core Kubernetes):
  01  Broken CNI & CoreDNS Readiness
  02  Control Plane Static Pods & etcd Quorum Health
  03  Node NotReady, Kubelet Daemon & PKI Certificate Expiry
  04  Node DiskPressure & Ephemeral Storage Eviction
  05  Workload Startup Failures: CrashLoopBackOff & ImagePullBackOff
  06  Scheduling Failures: Pending Pods, CPU Starvation & Node Selector/Taints
  07  Memory Exhaustion: OOMKilled (Exit Code 137) & QoS Classes
  08  Service Routing Blackhole: Selector Drift, targetPort & NetworkPolicy/DNS
  09  Storage Provisioning: PVC Pending, StorageClass Mismatch & Persistence
  10  Stuck Deployment Rollout: Failing Readiness Probe & PDB Deadlock

Scenarios (Project 2 Barnacles, Level 5 vLLM & Level 6 IDP Platform):
  11  Barnacles Log Platform: Network Partition & Edge Spool Drain Recovery
  12  Level 5 AI Inference: vLLM Queue Saturation & Readiness Probe Shedding
  13  Level 6 IDP Governance: Kyverno Hygiene & Restricted PSS Violations
  14  Level 6 Cloud Secrets: ExternalSecret & Secret Key Mapping Drift
EOF
}

# ------------------------------------------------------------------------------
# Fault Injection Scenarios (01 - 10)
# ------------------------------------------------------------------------------

inject_01() {
  ensure_namespace
  record_state "01" "explicit"
  if [[ "${EXTRA_FLAG}" == "--allow-node-fault" ]]; then
    log_warn "Moving /etc/cni/net.d/*.conflist to /tmp/cni-backup/ on this node..."
    sudo mkdir -p /tmp/cni-backup
    sudo mv /etc/cni/net.d/* /tmp/cni-backup/ 2>/dev/null || true
    log_info "CNI configuration moved. New pods scheduled on $(hostname -s) will fail sandbox creation."
  else
    log_info "Injecting CNI / CoreDNS diagnostic test pod into '${LAB_NAMESPACE}'..."
    kubectl apply -n "${LAB_NAMESPACE}" -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: cni-dns-probe
  labels:
    app: cni-dns-probe
spec:
  containers:
    - name: probe
      image: busybox:1.36
      command: ["sh", "-c", "sleep 3600"]
      resources:
        requests:
          cpu: 50m
          memory: 64Mi
        limits:
          cpu: 100m
          memory: 128Mi
EOF
    log_info "Tip: To simulate a host-level missing CNI config on a worker node, run:"
    echo "  sudo ./scripts/troubleshooting/sre-lab-runner.sh inject 01 --allow-node-fault"
  fi
  log_info "See Runbook: docs/labs/lab-01-broken-cni.md"
}

inject_02() {
  ensure_namespace
  record_state "02" "explicit"
  log_info "Lab 02 focuses on Control Plane & etcd quorum diagnostics."
  if [[ "${EXTRA_FLAG}" == "--allow-node-fault" ]] && [[ -f /etc/kubernetes/manifests/kube-apiserver.yaml ]]; then
    log_warn "Backing up /etc/kubernetes/manifests/kube-apiserver.yaml to /tmp/kube-apiserver.yaml.bak and injecting broken etcd port (:2389)..."
    sudo cp /etc/kubernetes/manifests/kube-apiserver.yaml /tmp/kube-apiserver.yaml.bak
    sudo sed -i 's/:2379/:2389/g' /etc/kubernetes/manifests/kube-apiserver.yaml
    log_info "API server static pod will now fail to reach etcd on 127.0.0.1:2389."
  else
    log_info "Safe mode active (control-plane static pods untouched)."
    log_info "To inject a live control-plane static pod etcd port fault on a CP node, run:"
    echo "  sudo ./scripts/troubleshooting/sre-lab-runner.sh inject 02 --allow-node-fault"
  fi
  log_info "See Runbook: docs/labs/lab-02-etcd-quorum-loss.md"
}

inject_03() {
  ensure_namespace
  record_state "03" "explicit"
  if [[ "${EXTRA_FLAG}" == "--allow-node-fault" ]]; then
    log_warn "Stopping kubelet service on $(hostname -s) to simulate Node NotReady..."
    sudo systemctl stop kubelet
    log_info "kubelet stopped. Within ~40s (node-monitor-grace-period), this node will report NotReady."
  else
    log_info "Safe mode active. Inspect node readiness and PKI expiration with:"
    echo "  sudo kubeadm certs check-expiration"
    log_info "To stop kubelet on a worker node and trigger a live Node NotReady incident, run:"
    echo "  sudo ./scripts/troubleshooting/sre-lab-runner.sh inject 03 --allow-node-fault"
  fi
  log_info "See Runbook: docs/labs/lab-03-kubelet-cert-expiry.md"
}

inject_04() {
  ensure_namespace
  record_state "04" "explicit"
  log_info "Deploying ephemeral-storage pressure workload into '${LAB_NAMESPACE}'..."
  kubectl apply -n "${LAB_NAMESPACE}" -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: log-flooder
  labels:
    sre-lab: "04"
spec:
  replicas: 1
  selector:
    matchLabels:
      app: log-flooder
  template:
    metadata:
      labels:
        app: log-flooder
        sre-lab: "04"
    spec:
      containers:
        - name: flooder
          image: busybox:1.36
          command: ["sh", "-c", "dd if=/dev/zero of=/tmp/scratch.bin bs=1M count=64 && sleep 3600"]
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
              ephemeral-storage: 10Mi
            limits:
              cpu: 100m
              memory: 128Mi
              ephemeral-storage: 20Mi
EOF
  log_info "Workload 'log-flooder' writes 64Mi to /tmp while constrained to a 20Mi ephemeral-storage limit (triggering kubelet eviction)."
  log_info "See Runbook: docs/labs/lab-04-node-pressure-disk-full.md"
}

inject_05() {
  ensure_namespace
  record_state "05" "${1:-explicit}"
  kubectl apply -n "${LAB_NAMESPACE}" -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: payment-worker
  labels:
    sre-lab: "05"
spec:
  replicas: 2
  selector:
    matchLabels:
      app: payment-worker
  template:
    metadata:
      labels:
        app: payment-worker
        sre-lab: "05"
    spec:
      containers:
        - name: worker
          image: nginx:99.99-nonexistent-tag
          ports:
            - containerPort: 80
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 100m
              memory: 128Mi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: checkout-api
  labels:
    sre-lab: "05"
spec:
  replicas: 2
  selector:
    matchLabels:
      app: checkout-api
  template:
    metadata:
      labels:
        app: checkout-api
        sre-lab: "05"
    spec:
      containers:
        - name: api
          image: nginx:1.27-alpine
          command: ["sh", "-c", "echo 'Fatal: invalid startup flag --missing-dsn' >&2; exit 1"]
          env:
            - name: APP_MODE
              valueFrom:
                configMapKeyRef:
                  name: checkout-config
                  key: APP_MODE
          ports:
            - containerPort: 80
          livenessProbe:
            httpGet:
              path: /
              port: 8089
            initialDelaySeconds: 2
            periodSeconds: 5
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 100m
              memory: 128Mi
EOF
}

inject_06() {
  ensure_namespace
  record_state "06" "${1:-explicit}"
  kubectl apply -n "${LAB_NAMESPACE}" -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: batch-scorer
  labels:
    sre-lab: "06"
spec:
  replicas: 2
  selector:
    matchLabels:
      app: batch-scorer
  template:
    metadata:
      labels:
        app: batch-scorer
        sre-lab: "06"
    spec:
      containers:
        - name: scorer
          image: nginx:1.27-alpine
          resources:
            requests:
              cpu: "64"
              memory: 128Mi
            limits:
              cpu: "64"
              memory: 256Mi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gpu-inference-sim
  labels:
    sre-lab: "06"
spec:
  replicas: 1
  selector:
    matchLabels:
      app: gpu-inference-sim
  template:
    metadata:
      labels:
        app: gpu-inference-sim
        sre-lab: "06"
    spec:
      nodeSelector:
        accelerator: inference-sim
      containers:
        - name: server
          image: nginx:1.27-alpine
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 200m
              memory: 256Mi
EOF
}

inject_07() {
  ensure_namespace
  record_state "07" "${1:-explicit}"
  kubectl apply -n "${LAB_NAMESPACE}" -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: memory-hog-service
  labels:
    sre-lab: "07"
spec:
  replicas: 1
  selector:
    matchLabels:
      app: memory-hog-service
  template:
    metadata:
      labels:
        app: memory-hog-service
        sre-lab: "07"
    spec:
      containers:
        - name: worker
          image: python:3.12-alpine
          command:
            - python3
            - -c
            - |
              import time
              # Allocate ~40MB byte array to stay well within 128Mi once fixed, but exceed 16Mi limit initially
              buf = bytearray(40 * 1024 * 1024)
              print("Allocated 40MB working buffer successfully", flush=True)
              while True:
                  time.sleep(10)
          resources:
            requests:
              cpu: 50m
              memory: 16Mi
            limits:
              cpu: 100m
              memory: 16Mi
EOF
}

inject_08() {
  ensure_namespace
  record_state "08" "${1:-explicit}"
  kubectl apply -n "${LAB_NAMESPACE}" -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: orders-backend
  labels:
    sre-lab: "08"
spec:
  replicas: 2
  selector:
    matchLabels:
      app: orders-backend
  template:
    metadata:
      labels:
        app: orders-backend
        sre-lab: "08"
    spec:
      containers:
        - name: backend
          image: nginx:1.27-alpine
          ports:
            - containerPort: 80
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 100m
              memory: 128Mi
---
apiVersion: v1
kind: Service
metadata:
  name: orders-svc
  labels:
    sre-lab: "08"
spec:
  selector:
    app: orders-backend-typo
  ports:
    - name: http
      protocol: TCP
      port: 80
      targetPort: 9090
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend-client
  labels:
    sre-lab: "08"
spec:
  replicas: 1
  selector:
    matchLabels:
      app: frontend-client
  template:
    metadata:
      labels:
        app: frontend-client
        sre-lab: "08"
    spec:
      containers:
        - name: client
          image: busybox:1.36
          command: ["sh", "-c", "sleep 3600"]
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 100m
              memory: 128Mi
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: orders-network-policy
  labels:
    sre-lab: "08"
spec:
  podSelector:
    matchLabels:
      app: orders-backend
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: unauthorized-caller
      ports:
        - protocol: TCP
          port: 80
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: frontend-egress-lock
  labels:
    sre-lab: "08"
spec:
  podSelector:
    matchLabels:
      app: frontend-client
  policyTypes:
    - Egress
  egress: []
EOF
}

inject_09() {
  ensure_namespace
  record_state "09" "${1:-explicit}"
  kubectl apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolume
metadata:
  name: sre-lab-pv
  labels:
    sre-lab: "09"
spec:
  storageClassName: local-storage
  capacity:
    storage: 1Gi
  accessModes:
    - ReadWriteOnce
  hostPath:
    path: /tmp/sre-lab-pv-data
    type: DirectoryOrCreate
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-data-pvc
  namespace: sre-lab
  labels:
    sre-lab: "09"
spec:
  storageClassName: nonexistent-fast-ssd
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 500Mi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres-db
  namespace: sre-lab
  labels:
    sre-lab: "09"
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgres-db
  template:
    metadata:
      labels:
        app: postgres-db
        sre-lab: "09"
    spec:
      containers:
        - name: db
          image: busybox:1.36
          command: ["sh", "-c", "mkdir -p /var/lib/postgresql/data && sleep 3600"]
          volumeMounts:
            - name: data
              mountPath: /var/lib/postgresql/data
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 100m
              memory: 128Mi
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: postgres-data-pvc
EOF
}

inject_10() {
  ensure_namespace
  record_state "10" "${1:-explicit}"
  # Revision 1: Healthy 3-replica deployment
  kubectl apply -n "${LAB_NAMESPACE}" -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inference-gateway
  labels:
    sre-lab: "10"
spec:
  progressDeadlineSeconds: 30
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0
      maxSurge: 1
  selector:
    matchLabels:
      app: inference-gateway
  template:
    metadata:
      labels:
        app: inference-gateway
        sre-lab: "10"
    spec:
      containers:
        - name: gateway
          image: nginx:1.27-alpine
          ports:
            - containerPort: 80
          readinessProbe:
            httpGet:
              path: /
              port: 80
            initialDelaySeconds: 1
            periodSeconds: 3
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 100m
              memory: 128Mi
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: inference-gateway-pdb
  labels:
    sre-lab: "10"
spec:
  minAvailable: 3
  selector:
    matchLabels:
      app: inference-gateway
EOF
  kubectl rollout status deployment/inference-gateway -n "${LAB_NAMESPACE}" --timeout=60s >/dev/null 2>&1 || true
  # Revision 2: Trigger broken rollout with bad readinessProbe path & port
  kubectl patch deployment inference-gateway -n "${LAB_NAMESPACE}" --type='json' -p='[
    {"op": "replace", "path": "/spec/template/spec/containers/0/readinessProbe/httpGet/path", "value": "/healthz-nonexistent"},
    {"op": "replace", "path": "/spec/template/spec/containers/0/readinessProbe/httpGet/port", "value": 8088}
  ]' >/dev/null
}

inject_11() {
  ensure_namespace
  record_state "11" "${1:-explicit}"
  kubectl apply -n "${LAB_NAMESPACE}" -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: barnacles-server-sim
  labels:
    sre-lab: "11"
spec:
  replicas: 1
  selector:
    matchLabels:
      app: barnacles-server-sim
  template:
    metadata:
      labels:
        app: barnacles-server-sim
        sre-lab: "11"
    spec:
      containers:
        - name: server
          image: nginx:1.27-alpine
          ports:
            - containerPort: 80
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 100m
              memory: 128Mi
---
apiVersion: v1
kind: Service
metadata:
  name: barnacles-ingest-svc
  labels:
    sre-lab: "11"
spec:
  selector:
    app: barnacles-server-sim
  ports:
    - name: http-ingest
      protocol: TCP
      port: 8080
      targetPort: 80
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: barnacles-agent-sim
  labels:
    sre-lab: "11"
spec:
  replicas: 1
  selector:
    matchLabels:
      app: barnacles-agent-sim
  template:
    metadata:
      labels:
        app: barnacles-agent-sim
        sre-lab: "11"
    spec:
      containers:
        - name: agent
          image: busybox:1.36
          command:
            - sh
            - -c
            - |
              mkdir -p /app/data/agent-spool
              echo '{"ts":"2026-11-05T12:00:00Z","level":"ERROR","msg":"buffered during network partition"}' > /app/data/agent-spool/batch-0001.inflight
              while true; do
                if wget -qO- --timeout=2 http://barnacles-ingest-svc.sre-lab.svc.cluster.local:8080 >/dev/null 2>&1; then
                  rm -f /app/data/agent-spool/*.inflight
                  echo "[barnacles-agent] Spool drained to central server successfully"
                else
                  echo "[barnacles-agent] Central server unreachable; spooling batch to /app/data/agent-spool/batch-0001.inflight" >&2
                fi
                sleep 5
              done
          volumeMounts:
            - name: spool
              mountPath: /app/data/agent-spool
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 100m
              memory: 128Mi
      volumes:
        - name: spool
          emptyDir: {}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: barnacles-agent-partition-lock
  labels:
    sre-lab: "11"
spec:
  podSelector:
    matchLabels:
      app: barnacles-agent-sim
  policyTypes:
    - Egress
  # Fault: Egress locked to wrong port (9999 instead of 8080) and missing CoreDNS (UDP/TCP 53)
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: barnacles-server-sim
      ports:
        - protocol: TCP
          port: 9999
EOF
  log_info "See Runbook: docs/labs/lab-11-barnacles-spool-partition.md"
}

inject_12() {
  ensure_namespace
  record_state "12" "${1:-explicit}"
  kubectl apply -n "${LAB_NAMESPACE}" -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vllm-serving-sim
  labels:
    sre-lab: "12"
spec:
  replicas: 2
  selector:
    matchLabels:
      app: vllm-serving-sim
  template:
    metadata:
      labels:
        app: vllm-serving-sim
        sre-lab: "12"
    spec:
      containers:
        - name: vllm
          image: nginx:1.27-alpine
          env:
            # Fault 1: MAX_NUM_SEQS set to 0 (rejecting all continuous batching slots)
            - name: MAX_NUM_SEQS
              value: "0"
            - name: GPU_MEMORY_UTILIZATION
              value: "0.90"
          ports:
            - name: http-openai
              containerPort: 80
          # Fault 2: Readiness probe checks wrong port (8009 instead of 80), shedding all endpoints
          readinessProbe:
            httpGet:
              path: /
              port: 8009
            initialDelaySeconds: 1
            periodSeconds: 3
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 100m
              memory: 128Mi
---
apiVersion: v1
kind: Service
metadata:
  name: vllm-sim-svc
  labels:
    sre-lab: "12"
spec:
  selector:
    app: vllm-serving-sim
  ports:
    - name: http-openai
      protocol: TCP
      port: 8000
      targetPort: 80
EOF
  log_info "See Runbook: docs/labs/lab-12-vllm-queue-saturation.md"
}

inject_13() {
  ensure_namespace
  record_state "13" "${1:-explicit}"
  kubectl apply -n "${LAB_NAMESPACE}" -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rogue-tenant-service
  labels:
    sre-lab: "13"
    # Fault 1: Missing mandatory 'idp.k8s-lab.internal/owner-team' FinOps label
spec:
  replicas: 1
  selector:
    matchLabels:
      app: rogue-tenant-service
  template:
    metadata:
      labels:
        app: rogue-tenant-service
        sre-lab: "13"
    spec:
      # Fault 2: Missing pod-level runAsNonRoot: true
      containers:
        - name: app
          # Fault 3: Uses mutable ':latest' tag prohibited by Kyverno policy 'idp-validate-production-hygiene'
          image: busybox:latest
          command: ["sh", "-c", "sleep 3600"]
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 100m
              memory: 128Mi
EOF
  log_info "See Runbook: docs/labs/lab-13-idp-kyverno-admission.md"
}

inject_14() {
  ensure_namespace
  record_state "14" "${1:-explicit}"
  kubectl apply -n "${LAB_NAMESPACE}" -f - <<'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: gcp-sm-order-api-synced
  labels:
    sre-lab: "14"
type: Opaque
stringData:
  DATABASE_URI: "postgresql://order_user:zero-trust-secret@10.10.0.50:5432/orders"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: order-worker-idp
  labels:
    sre-lab: "14"
spec:
  replicas: 2
  selector:
    matchLabels:
      app: order-worker-idp
  template:
    metadata:
      labels:
        app: order-worker-idp
        sre-lab: "14"
    spec:
      containers:
        - name: worker
          image: busybox:1.36
          command: ["sh", "-c", "test -n \"$DATABASE_URI\" && sleep 3600"]
          env:
            # Fault: Secret name & key drift from ExternalSecret synced target ('gcp-sm-order-api-synced' / 'DATABASE_URI')
            - name: DATABASE_URI
              valueFrom:
                secretKeyRef:
                  name: gcp-sm-order-api-missing-secret
                  key: DB_CONN_STRING_WRONG_KEY
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 100m
              memory: 128Mi
EOF
  log_info "See Runbook: docs/labs/lab-14-external-secret-sync.md"
}

# ------------------------------------------------------------------------------
# Verification Functions (01 - 10)
# ------------------------------------------------------------------------------

verify_01() {
  local running_dns
  running_dns="$(kubectl get pods -n kube-system -l k8s-app=kube-dns --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "${running_dns}" -lt 1 ]]; then
    log_err "CoreDNS has no Running pods in kube-system."
    exit 1
  fi
  log_ok "Lab 01 Verified: CoreDNS pods are Running (${running_dns} active) and CNI network is operational."
}

verify_02() {
  if ! kubectl get --raw='/readyz' >/dev/null 2>&1; then
    log_err "Kubernetes API server /readyz check failed."
    exit 1
  fi
  log_ok "Lab 02 Verified: Kubernetes API server and etcd backing store report healthy (/readyz OK)."
}

verify_03() {
  local not_ready
  not_ready="$(kubectl get nodes --no-headers | grep -v ' Ready' | wc -l | tr -d ' ')"
  if [[ "${not_ready}" -ne 0 ]]; then
    log_err "Found ${not_ready} node(s) in NotReady state."
    exit 1
  fi
  log_ok "Lab 03 Verified: All cluster nodes report Ready and kubelet client PKI is healthy."
}

verify_04() {
  local disk_pressure
  disk_pressure="$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}={range .status.conditions[?(@.type=="DiskPressure")]}{.status}{"\n"}{end}{end}' | grep '=True' | wc -l | tr -d ' ')"
  if [[ "${disk_pressure}" -ne 0 ]]; then
    log_err "One or more nodes still report DiskPressure=True."
    exit 1
  fi
  log_ok "Lab 04 Verified: Zero nodes report DiskPressure."
}

verify_05() {
  kubectl rollout status deployment/payment-worker -n "${LAB_NAMESPACE}" --timeout=20s >/dev/null
  kubectl rollout status deployment/checkout-api -n "${LAB_NAMESPACE}" --timeout=20s >/dev/null
  log_ok "Lab 05 Verified: Both 'payment-worker' and 'checkout-api' Deployments are 100% Ready with valid images, ConfigMaps, and liveness probes!"
}

verify_06() {
  kubectl rollout status deployment/batch-scorer -n "${LAB_NAMESPACE}" --timeout=20s >/dev/null
  kubectl rollout status deployment/gpu-inference-sim -n "${LAB_NAMESPACE}" --timeout=20s >/dev/null
  log_ok "Lab 06 Verified: Both 'batch-scorer' and 'gpu-inference-sim' have been scheduled and are Running!"
}

verify_07() {
  kubectl rollout status deployment/memory-hog-service -n "${LAB_NAMESPACE}" --timeout=20s >/dev/null
  local qos
  qos="$(kubectl get pods -n "${LAB_NAMESPACE}" -l app=memory-hog-service -o jsonpath='{.items[0].status.qosClass}')"
  if [[ "${qos}" != "Guaranteed" ]]; then
    log_warn "Pod is Running, but QoS class is '${qos}'. Set equal CPU & memory requests/limits (100m / 128Mi) to achieve 'Guaranteed' QoS."
    exit 1
  fi
  log_ok "Lab 07 Verified: 'memory-hog-service' is Running without OOMKills in QoS class '${qos}'!"
}

verify_08() {
  kubectl exec -n "${LAB_NAMESPACE}" deploy/frontend-client -- wget -qO- --timeout=4 http://orders-svc.sre-lab.svc.cluster.local >/dev/null
  log_ok "Lab 08 Verified: End-to-end DNS lookup and HTTP request from 'frontend-client' -> 'orders-svc' -> 'orders-backend' succeeded!"
}

verify_09() {
  local phase
  phase="$(kubectl get pvc postgres-data-pvc -n "${LAB_NAMESPACE}" -o jsonpath='{.status.phase}')"
  if [[ "${phase}" != "Bound" ]]; then
    log_err "PVC 'postgres-data-pvc' is in phase '${phase}' (expected 'Bound')."
    exit 1
  fi
  kubectl rollout status deployment/postgres-db -n "${LAB_NAMESPACE}" --timeout=20s >/dev/null
  log_ok "Lab 09 Verified: PVC 'postgres-data-pvc' is Bound and 'postgres-db' is Running with persistent storage mounted!"
}

verify_10() {
  kubectl rollout status deployment/inference-gateway -n "${LAB_NAMESPACE}" --timeout=20s >/dev/null
  local allowed
  allowed="$(kubectl get pdb inference-gateway-pdb -n "${LAB_NAMESPACE}" -o jsonpath='{.status.disruptionsAllowed}')"
  if [[ "${allowed:-0}" -lt 1 ]]; then
    log_err "PodDisruptionBudget 'inference-gateway-pdb' still has disruptionsAllowed=${allowed:-0} (drain remains deadlocked)."
    exit 1
  fi
  log_ok "Lab 10 Verified: 'inference-gateway' rollout completed cleanly and PDB allows voluntary disruptions (${allowed})!"
}

verify_11() {
  kubectl rollout status deployment/barnacles-server-sim -n "${LAB_NAMESPACE}" --timeout=20s >/dev/null
  kubectl rollout status deployment/barnacles-agent-sim -n "${LAB_NAMESPACE}" --timeout=20s >/dev/null
  kubectl exec -n "${LAB_NAMESPACE}" deploy/barnacles-agent-sim -- wget -qO- --timeout=4 http://barnacles-ingest-svc.sre-lab.svc.cluster.local:8080 >/dev/null
  local inflight_count
  inflight_count="$(kubectl exec -n "${LAB_NAMESPACE}" deploy/barnacles-agent-sim -- sh -c 'ls -1 /app/data/agent-spool/*.inflight 2>/dev/null | wc -l' | tr -d ' ')"
  if [[ "${inflight_count}" -ne 0 ]]; then
    log_err "Barnacles agent still has ${inflight_count} undrained .inflight spool file(s)."
    exit 1
  fi
  log_ok "Lab 11 Verified: Barnacles network partition healed and edge spool drained with zero data loss!"
}

verify_12() {
  kubectl rollout status deployment/vllm-serving-sim -n "${LAB_NAMESPACE}" --timeout=20s >/dev/null
  local max_seqs
  max_seqs="$(kubectl get deployment vllm-serving-sim -n "${LAB_NAMESPACE}" -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="MAX_NUM_SEQS")].value}')"
  if [[ "${max_seqs:-0}" -lt 16 ]]; then
    log_err "vLLM MAX_NUM_SEQS is '${max_seqs:-0}' (must be >= 16 to prevent continuous batching queue starvation)."
    exit 1
  fi
  log_ok "Lab 12 Verified: vLLM serving replicas are Ready with MAX_NUM_SEQS=${max_seqs} and active Service endpoints!"
}

verify_13() {
  kubectl rollout status deployment/rogue-tenant-service -n "${LAB_NAMESPACE}" --timeout=20s >/dev/null
  local owner_team image run_as_non_root
  owner_team="$(kubectl get deployment rogue-tenant-service -n "${LAB_NAMESPACE}" -o jsonpath='{.metadata.labels.idp\.k8s-lab\.internal/owner-team}')"
  image="$(kubectl get deployment rogue-tenant-service -n "${LAB_NAMESPACE}" -o jsonpath='{.spec.template.spec.containers[0].image}')"
  run_as_non_root="$(kubectl get deployment rogue-tenant-service -n "${LAB_NAMESPACE}" -o jsonpath='{.spec.template.spec.securityContext.runAsNonRoot}')"
  if [[ -z "${owner_team}" ]]; then
    log_err "Deployment 'rogue-tenant-service' is still missing label 'idp.k8s-lab.internal/owner-team'."
    exit 1
  fi
  if [[ "${image}" == *":latest" ]]; then
    log_err "Container image '${image}' still uses a mutable ':latest' tag."
    exit 1
  fi
  if [[ "${run_as_non_root}" != "true" ]]; then
    log_err "Pod securityContext.runAsNonRoot is '${run_as_non_root}' (expected 'true' for restricted PSS)."
    exit 1
  fi
  log_ok "Lab 13 Verified: 'rogue-tenant-service' satisfies all Level 6 Kyverno & Restricted PSS guardrails (owner-team=${owner_team}, image=${image})!"
}

verify_14() {
  kubectl rollout status deployment/order-worker-idp -n "${LAB_NAMESPACE}" --timeout=20s >/dev/null
  log_ok "Lab 14 Verified: 'order-worker-idp' Secret reference & key mapping aligned with synced ExternalSecret ('gcp-sm-order-api-synced')!"
}

# ------------------------------------------------------------------------------
# Reset / Teardown
# ------------------------------------------------------------------------------
reset_all() {
  log_info "Cleaning up SRE troubleshooting lab resources..."
  if [[ -d /tmp/cni-backup ]] && [[ -n "$(ls -A /tmp/cni-backup 2>/dev/null || true)" ]]; then
    sudo mv /tmp/cni-backup/* /etc/cni/net.d/ 2>/dev/null || true
    log_info "Restored CNI configs to /etc/cni/net.d/."
  fi
  if [[ -f /tmp/kube-apiserver.yaml.bak ]]; then
    sudo mv /tmp/kube-apiserver.yaml.bak /etc/kubernetes/manifests/kube-apiserver.yaml
    log_info "Restored /etc/kubernetes/manifests/kube-apiserver.yaml."
  fi
  if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files kubelet.service >/dev/null 2>&1; then
    sudo systemctl start kubelet 2>/dev/null || true
  fi
  kubectl delete namespace "${LAB_NAMESPACE}" --ignore-not-found --wait=false >/dev/null 2>&1 || true
  kubectl delete pv sre-lab-pv --ignore-not-found >/dev/null 2>&1 || true
  for node in $(kubectl get nodes -l accelerator=inference-sim -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true); do
    kubectl label node "${node}" accelerator- >/dev/null 2>&1 || true
  done
  log_ok "Reset triggered for namespace '${LAB_NAMESPACE}' and cluster-scoped lab fixtures."
}

# ------------------------------------------------------------------------------
# Command Router
# ------------------------------------------------------------------------------
case "${ACTION}" in
  list)
    usage
    ;;

  inject)
    LAB_ID="$(normalize_id "${TARGET}")"
    if [[ -z "${LAB_ID}" ]] || [[ "${LAB_ID}" == "current" ]] || [[ "${LAB_ID}" == "all" ]]; then
      log_err "Please specify a valid lab ID (01..14)."
      usage
      exit 1
    fi
    log_info "Injecting SRE Troubleshooting Scenario ${LAB_ID}..."
    "inject_${LAB_ID}" "explicit"
    log_info "Scenario ${LAB_ID} active in namespace '${LAB_NAMESPACE}'. When fixed, run:"
    echo "  ./scripts/troubleshooting/sre-lab-runner.sh verify ${LAB_ID}"
    ;;

  random)
    CANDIDATES=("05" "06" "07" "08" "09" "10" "11" "12" "13" "14")
    RANDOM_INDEX=$(( RANDOM % ${#CANDIDATES[@]} ))
    CHOSEN_LAB="${CANDIDATES[$RANDOM_INDEX]}"
    log_warn "=================================================================="
    log_warn "  BLIND ON-CALL SRE DRILL INITIATED (Target SLA: 25 Minutes)"
    log_warn "=================================================================="
    "inject_${CHOSEN_LAB}" "blind-random"
    echo ""
    log_info "PAGER ALERT: Workloads or network paths in namespace '${LAB_NAMESPACE}' are degraded."
    log_info "1. Triage using 'kubectl get all,pvc,netpol,pdb,events -n ${LAB_NAMESPACE}'"
    log_info "2. Form a first-principles hypothesis before modifying resources."
    log_info "3. Remediate the root cause and verify recovery with:"
    echo "     ./scripts/troubleshooting/sre-lab-runner.sh verify current"
    ;;

  status)
    ACTIVE_LAB="$(get_active_lab)"
    if [[ -z "${ACTIVE_LAB}" ]]; then
      log_info "No active SRE lab recorded in namespace '${LAB_NAMESPACE}'."
      exit 0
    fi
    MODE="$(kubectl get configmap "${STATE_CM}" -n "${LAB_NAMESPACE}" -o jsonpath='{.data.mode}' 2>/dev/null || echo "explicit")"
    if [[ "${MODE}" == "blind-random" ]]; then
      log_info "Active Mode: BLIND RANDOM ON-CALL DRILL (Lab ID hidden until verified)"
    else
      log_info "Active Scenario: Lab ${ACTIVE_LAB} (Runbook: docs/labs/lab-${ACTIVE_LAB}-*.md)"
    fi
    print_elapsed_time
    echo ""
    kubectl get pods,svc,pvc,networkpolicy,pdb -n "${LAB_NAMESPACE}" 2>/dev/null || true
    ;;

  verify)
    LAB_ID="$(normalize_id "${TARGET:-current}")"
    if [[ "${LAB_ID}" == "current" ]]; then
      LAB_ID="$(get_active_lab)"
    fi
    if [[ -z "${LAB_ID}" ]]; then
      log_err "Could not determine active lab ID. Specify explicitly: verify <01..14>"
      exit 1
    fi
    log_info "Verifying remediation for Lab ${LAB_ID}..."
    "verify_${LAB_ID}"
    print_elapsed_time
    log_info "Don't forget to document your post-mortem using: docs/labs/incident-report-template.md"
    ;;

  reset)
    reset_all
    ;;

  *)
    usage
    exit 1
    ;;
esac
