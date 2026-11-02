# Lab 08: Service Routing, EndpointSlices, CoreDNS & NetworkPolicy Blackholes

## Objective
Diagnose and repair a broken multi-tier communication path (`frontend-client` → `orders-svc` → `orders-backend` Pods) caused by:
1. **Service Selector Drift**: Empty `Endpoints` / `EndpointSlices` due to mismatched label selectors.
2. **Port Mismatch**: Service `targetPort` pointing to the wrong container listening port.
3. **NetworkPolicy Blackhole**: A restrictive `NetworkPolicy` blocking ingress traffic to the backend or blocking UDP/TCP port `53` egress to `CoreDNS`.

---

## First-Principles Mental Model
Trace the packet path from a client Pod calling `http://orders-svc.sre-lab.svc.cluster.local`:
1. **DNS Resolution (`CoreDNS`)**: The client Pod checks `/etc/resolv.conf` and sends a UDP/TCP port `53` DNS query to `kube-dns` (`10.96.0.10`). If an egress `NetworkPolicy` blocks port `53`, DNS lookup hangs or fails with `Temporary failure in name resolution`.
2. **Virtual IP Translation (`kube-proxy`)**: `CoreDNS` returns the Service `ClusterIP`. When the client connects to `ClusterIP:80`, the Linux kernel on the client's node intercepts the packet via **`iptables` or `IPVS`** rules programmed by `kube-proxy` and DNATs the destination IP:Port to a healthy Pod `IP:targetPort` listed in the Service's **`EndpointSlice`**.
   - If the Service `selector` doesn't match any Pod labels, the `EndpointSlice` is empty and connections fail immediately (`Connection refused` / `No route to host`).
   - If `targetPort` doesn't match the container's listening socket (`ss -tulpn`), the Pod's network namespace rejects the TCP SYN with `RST` (`Connection refused`).
3. **CNI & NetworkPolicy Enforcement**: If an ingress `NetworkPolicy` selects the destination Pod without allowing the client Pod's labels/port, packets are silently dropped (`Connection timed out`).

---

## Automated Failure Injection

```bash
./scripts/troubleshooting/sre-lab-runner.sh inject 08
```

---

## Failure Symptoms
1. All `orders-backend` Pods are `1/1 Running`.
2. However, executing a request from `frontend-client` to `http://orders-svc` fails with DNS timeout, `Connection refused`, or `Connection timed out`.

---

## Diagnosis Workflow

### Step 1: Test DNS & HTTP Connectivity from the Client Pod
```bash
kubectl exec -n sre-lab deploy/frontend-client -- nslookup orders-svc.sre-lab.svc.cluster.local
kubectl exec -n sre-lab deploy/frontend-client -- wget -qO- --timeout=3 http://orders-svc.sre-lab.svc.cluster.local
```

### Step 2: Check NetworkPolicies (Why DNS or HTTP Times Out)
```bash
kubectl get networkpolicy -n sre-lab
kubectl describe networkpolicy -n sre-lab
```
Notice if a policy blocks egress to `kube-system` port `53` (DNS) or blocks ingress from `app: frontend-client` to `app: orders-backend`.

### Step 3: Inspect Service Selectors & EndpointSlices
```bash
kubectl get svc orders-svc -n sre-lab -o wide
kubectl get endpoints orders-svc -n sre-lab
kubectl get endpointslices -n sre-lab -l kubernetes.io/service-name=orders-svc
kubectl get pods -n sre-lab --show-labels
```
- If `ENDPOINTS` is `<none>`, compare `svc.spec.selector` against the actual Pod labels (`app=orders-backend`).
- Compare `svc.spec.ports[].targetPort` against the port the container actually listens on (`80`).

### Step 4: Linux Networking Deep Dive (Node-Level Inspection)
On the worker node running `orders-backend`, inspect the container's network namespace and `iptables` rules:
```bash
# Inspect listening sockets inside the Pod or on the node via nsenter:
kubectl exec -n sre-lab deploy/orders-backend -- sh -c "netstat -tulpn || ss -tulpn"

# On the worker node, inspect kube-proxy iptables rules for orders-svc:
sudo iptables-save | grep orders-svc
```

---

## Remediation

### 1. Fix the Service Selector & `targetPort`
Patch `orders-svc` so its selector matches `app: orders-backend` and its `targetPort` matches port `80`:
```bash
kubectl patch svc orders-svc -n sre-lab --type='merge' -p='{
  "spec": {
    "selector": {"app": "orders-backend"},
    "ports": [{"name": "http", "port": 80, "targetPort": 80, "protocol": "TCP"}]
  }
}'
```
Verify `kubectl get endpoints orders-svc -n sre-lab` now lists Pod IPs!

### 2. Fix the Restrictive NetworkPolicy
Update the `NetworkPolicy` in `sre-lab` to allow DNS egress (UDP/TCP `53`) and allow ingress from `app: frontend-client` to `app: orders-backend` on TCP port `80`:
```bash
kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: orders-network-policy
  namespace: sre-lab
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
              app: frontend-client
      ports:
        - protocol: TCP
          port: 80
EOF
kubectl delete networkpolicy frontend-egress-lock -n sre-lab --ignore-not-found
```

### 3. Verify End-to-End Connectivity
```bash
./scripts/troubleshooting/sre-lab-runner.sh verify 08
```
