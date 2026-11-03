# Day 2 Walkthrough (Nov 3): API Server, `etcd` & Reconciliation Loops

> **Time Allocation (180 mins):**
> - **Conceptual Understanding (`35 min`)**: Declarative vs. imperative systems, RESTful API machinery (`Group/Version/Resource`), `etcd` MVCC & watches, and level-triggered reconciliation loops.
> - **Hands-On Engineering (`100 min`)**: Trace API calls (`-v=8`), inspect raw keys inside `etcd`, compare unmanaged Pod deletion vs. `Deployment` → `ReplicaSet` → `Pod` self-healing, and inspect `ownerReferences`.
> - **Troubleshooting (`25 min`)**: Simulate `etcd` quorum or kubelet certificate disruption ([Lab 02](../labs/lab-02-etcd-quorum-loss.md) / [Lab 03](../labs/lab-03-kubelet-cert-expiry.md)).
> - **Engineering Journal (`20 min`)**: Answer the Day 2 verification test in your journal ([`journal-template.md`](journal-template.md)).

---

## Part 1: Conceptual Understanding (35 Minutes)

### The 5 First-Principles Questions for Day 2
1. **What problem does declarative state + level-triggered reconciliation solve?**
   - In an **edge-triggered** system, if a controller misses a single event (e.g., due to a temporary network blip or process restart), the system drifts permanently out of sync.
   - In Kubernetes' **level-triggered** design, controllers continuously compare **Desired State** (`spec` in `etcd`) against **Actual State** (`status` reported by nodes/kubelets) via list-watch informers (`resourceVersion`). Even if `kube-controller-manager` crashes and restarts 10 minutes later, it lists current state and reconciles the diff automatically.
2. **Which component is allowed to talk directly to `etcd`?**
   - **Only `kube-apiserver`**. Every other component (`kube-scheduler`, `kube-controller-manager`, `kubelet`, `kube-proxy`, `kubectl`) reads and mutates state exclusively through `kube-apiserver`'s authenticated, RBAC-authorized, admission-validated HTTPS API.
3. **How do `Deployment`, `ReplicaSet`, and `Pod` relate via `ownerReferences`?**
   - A `Deployment` does **not** create Pods directly.
   - `deployment-controller` creates a `ReplicaSet` with `metadata.ownerReferences` pointing to the `Deployment` UID (and a pod-template hash label).
   - `replicaset-controller` creates `Pod` objects with `metadata.ownerReferences` pointing to the `ReplicaSet` UID.

---

## Part 2: Hands-On Engineering Lab (100 Minutes)

### Step 1: Trace `kubectl` REST API Machinery (`-v=8`)
Observe how `kubectl` translates commands into HTTP calls against `/api/v1` and `/apis/apps/v1`:
```bash
kubectl get nodes -v=6
kubectl get deployments -n default -v=8 2>&1 | grep -E "GET|Response Status"
```

### Step 2: Create a Standalone (Unmanaged) Pod vs. a Deployment
1. Create an unmanaged Pod using declarative YAML:
   ```bash
   cat <<'EOF' | kubectl apply -f -
   apiVersion: v1
   kind: Pod
   metadata:
     name: standalone-nginx
     labels:
       app: standalone-nginx
   spec:
     containers:
       - name: nginx
         image: nginx:1.27-alpine
         ports:
           - containerPort: 80
   EOF
   ```
2. Inspect its stored representation in `etcd` via the API server (notice `metadata.uid`, `metadata.resourceVersion`, `spec.nodeName`, and the absence of `metadata.ownerReferences`):
   ```bash
   kubectl get pod standalone-nginx -o yaml | grep -E "uid:|resourceVersion:|nodeName:|ownerReferences" -A 3
   ```
3. Delete the unmanaged Pod and verify it is gone forever:
   ```bash
   kubectl delete pod standalone-nginx
   kubectl get pod standalone-nginx
   ```

### Step 3: Observe Controller Reconciliation in Real Time
1. Open a second terminal watching cluster events and pods:
   ```bash
   kubectl get events --watch --sort-by=.metadata.creationTimestamp
   ```
2. Create a 3-replica `Deployment`:
   ```bash
   kubectl create deployment reconciled-nginx --image=nginx:1.27-alpine --replicas=3
   ```
3. Inspect the `ownerReferences` chain from `Pod` → `ReplicaSet` → `Deployment`:
   ```bash
   POD_NAME=$(kubectl get pods -l app=reconciled-nginx -o jsonpath='{.items[0].metadata.name}')
   kubectl get pod "${POD_NAME}" -o jsonpath='{.metadata.ownerReferences}' ; echo ""

   RS_NAME=$(kubectl get rs -l app=reconciled-nginx -o jsonpath='{.items[0].metadata.name}')
   kubectl get rs "${RS_NAME}" -o jsonpath='{.metadata.ownerReferences}' ; echo ""
   ```
4. Delete one Pod and immediately watch `replicaset-controller` detect the `2/3` drift and create a replacement Pod within milliseconds:
   ```bash
   kubectl delete pod "${POD_NAME}" --wait=false
   kubectl get pods -l app=reconciled-nginx -w
   ```

### Step 4: Inspect Keyspace Directly Inside `etcd`
On your control plane node, query `etcd` directly using `etcdctl` inside the `etcd` static Pod container:
```bash
ETCD_POD="etcd-$(hostname)"
sudo kubectl exec -n kube-system "${ETCD_POD}" -- sh -c \
  "ETCDCTL_API=3 etcdctl \
   --endpoints=https://127.0.0.1:2379 \
   --cacert=/etc/kubernetes/pki/etcd/ca.crt \
   --cert=/etc/kubernetes/pki/etcd/server.crt \
   --key=/etc/kubernetes/pki/etcd/server.key \
   get /registry/deployments/default/reconciled-nginx --prefix --keys-only"
```

Cleanup when finished:
```bash
kubectl delete deployment reconciled-nginx
```

---

## Part 3: Troubleshooting Exercise (25 Minutes)

Run **Lab 03 (Kubelet Certificate / Auth Failure)** or **Lab 02 (`etcd` Quorum Loss)** using the SRE lab runner:
```bash
./scripts/troubleshooting/sre-lab-runner.sh inject 03
# Diagnose using systemctl status kubelet, journalctl -u kubelet -xe, and openssl x509
./scripts/troubleshooting/sre-lab-runner.sh verify 03
```

---

## Part 4: End-of-Day Test (20 Minutes — Engineering Journal)

Write out in your engineering journal:
1. **What is the architectural difference between creating an individual `Pod` and managing Pods through a `Deployment`?**
   - A standalone `Pod` is a single one-shot record in `/registry/pods/<ns>/<name>` with no controller watching its replica count; if the Pod is deleted or its worker node dies, nothing recreates it.
   - A `Deployment` declares a desired replica count and pod template, reconciled continuously by `deployment-controller` (which manages `ReplicaSet` rollouts/revisions) and `replicaset-controller` (which watches matching Pods by label selector + `ownerReferences` and creates/deletes Pods whenever actual count != `spec.replicas`).
