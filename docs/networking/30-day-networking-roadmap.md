# 30-Day Kubernetes & Linux Networking Deep-Dive Roadmap (`docs/networking`)

> **Engineering Philosophy:** Do not treat Kubernetes networking as a separate technology—understand **Linux networking** first. Networking is one of the primary areas that separates a Staff/Senior Platform & AI Infrastructure Engineer from someone who primarily deploys YAML.

---

## 1. The 4-Week (30-Day) Structured Progression

| Week | Days | Focus Domain | Weekly Deliverable in `tf-gcp-k8s-lab` |
| :--- | :---: | :--- | :--- |
| **Week 1** | Days 1–7 | **Linux Networking Internals & Packet Foundations** | Build a 2-container Linux network namespace + `veth` + bridge + `iptables` NAT topology from scratch without Docker/K8s. |
| **Week 2** | Days 8–14 | **CNI Architecture, Pod-to-Pod Routing & Overlay Networks** | Trace a cross-node Pod-to-Pod packet hop-by-hop (`veth` → `cni0` → `flannel.1` VXLAN UDP `:8472` → GCP VPC) using [`trace-packet-path.sh`](../../scripts/networking/trace-packet-path.sh). |
| **Week 3** | Days 15–22 | **Services, `kube-proxy`, `EndpointSlices` & `CoreDNS`** | Trace `KUBE-SERVICES` / `KUBE-SVC-*` / `KUBE-SEP-*` `iptables` chains, `ndots:5` DNS resolution latency, and Headless vs. `ClusterIP` behavior. |
| **Week 4** | Days 23–30 | **North-South (`Ingress` / `Gateway API`), `NetworkPolicies` & 10 Failure Drills** | Deploy North-South routing + East-West zero-trust microsegmentation ([`02-gateway-and-ingress-lab.yaml`](../../kubernetes/networking/02-gateway-and-ingress-lab.yaml)) and resolve 10 network failures without hints. |

---

## 2. Linux Networking Toolkit (Must-Master Commands)

Before debugging a Service or CNI plugin, verify the underlying Linux network stack on the node:

```bash
# 1. Interfaces, IP addresses, and link state (MTU, UP/DOWN, MAC)
ip -br link show
ip -br addr show
ethtool -S eth0

# 2. Routing table & policy routing
ip route show table main
ip route get 10.244.1.5

# 3. Neighbor / ARP table (critical for VXLAN inner L2 MAC resolution)
ip neigh show

# 4. Active listening sockets & owning PIDs
sudo ss -tulpn

# 5. Network namespaces (inspect Pod network sandboxes from the host)
sudo lsns -t net
sudo nsenter -t <container-pid> -n ip addr
sudo nsenter -t <container-pid> -n ss -tulpn

# 6. iptables / nftables chains (kube-proxy Service VIP translation)
sudo iptables-save | grep -E "KUBE-SERVICES|KUBE-SVC|KUBE-SEP"
sudo nft list ruleset

# 7. Connection tracking (NAT state table & conntrack exhaustion checks)
sudo conntrack -L | head -n 20
sudo conntrack -S
cat /proc/sys/net/netfilter/nf_conntrack_count /proc/sys/net/netfilter/nf_conntrack_max

# 8. Live packet capture across host, bridge, VXLAN, and veth interfaces
sudo tcpdump -nn -i any host 10.244.1.5 and port 80
sudo tcpdump -nn -i eth0 udp port 8472
```

---

## 3. Week-by-Week Curriculum & Hands-On Labs

### Week 1 (Days 1–7): Linux Networking Internals

#### Conceptual Check (First Principles)
1. **What is a Linux network namespace (`netns`)?** An isolated copy of the kernel networking stack: its own loopback (`lo`), network interfaces, routing tables, ARP tables, `iptables`/`nftables` rules, and socket port space.
2. **Why does a Kubernetes Pod have a single IP shared by all containers in the Pod?** Because `containerd` creates a single pause/sandbox container that owns the `net` namespace, and every application/sidecar container in the Pod joins that exact same `net` namespace.
3. **How does a packet leave a Pod's isolated network namespace?** Via a **virtual Ethernet (`veth`) pair**—anvirtual pipe with one end (`eth0`) inside the Pod's `netns` and the peer end (`vethXXXX`) plugged into a Linux bridge (`cni0`) in the host root `netns`.

#### Week 1 Hands-On Deliverable: Build a Container Network by Hand
Run these commands in a scratch VM (or clean up afterward) to prove how CNI works under the hood:
```bash
# Create two isolated network namespaces
sudo ip netns add net-a
sudo ip netns add net-b

# Create a host Linux bridge
sudo ip link add br-lab type bridge
sudo ip link set br-lab up
sudo ip addr add 10.200.0.1/24 dev br-lab

# Create veth pairs and attach one end to each namespace, the other to br-lab
sudo ip link add veth-a type veth peer name veth-a-br
sudo ip link set veth-a netns net-a
sudo ip link set veth-a-br master br-lab
sudo ip link set veth-a-br up

sudo ip link add veth-b type veth peer name veth-b-br
sudo ip link set veth-b netns net-b
sudo ip link set veth-b-br master br-lab
sudo ip link set veth-b-br up

# Configure IPs and default routes inside each namespace
sudo ip netns exec net-a ip addr add 10.200.0.2/24 dev veth-a
sudo ip netns exec net-a ip link set veth-a up
sudo ip netns exec net-a ip link set lo up
sudo ip netns exec net-a ip route add default via 10.200.0.1

sudo ip netns exec net-b ip addr add 10.200.0.3/24 dev veth-b
sudo ip netns exec net-b ip link set veth-b up
sudo ip netns exec net-b ip link set lo up
sudo ip netns exec net-b ip route add default via 10.200.0.1

# Verify east-west packet delivery
sudo ip netns exec net-a ping -c 3 10.200.0.3

# Cleanup
sudo ip netns del net-a && sudo ip netns del net-b && sudo ip link del br-lab
```

---

### Week 2 (Days 8–14): CNI Architecture & Cross-Node Pod-to-Pod Packet Walk

#### Conceptual Check
1. **What happens when Pod A (`10.244.1.10` on `worker-01`) sends a packet to Pod B (`10.244.2.15` on `worker-02`)?**
   ```text
   [Pod A eth0 (10.244.1.10)]
         │  default route -> 10.244.1.1
         ▼
   [Host vethXXXX -> Bridge cni0 (10.244.1.1/24)]
         │  host route: 10.244.2.0/24 via 10.244.2.0 dev flannel.1 onlink
         ▼
   [flannel.1 VTEP (VXLAN encapsulation)]
         │  FDB + ARP lookup maps 10.244.2.0 VTEP MAC -> worker-02 internal IP (10.10.0.12)
         ▼
   [worker-01 eth0 (10.10.0.11) -> UDP Port 8472 -> GCP VPC -> worker-02 eth0 (10.10.0.12)]
         │  Kernel decapsulates VXLAN UDP :8472 packet
         ▼
   [worker-02 flannel.1 -> Bridge cni0 (10.244.2.1) -> vethYYYY -> Pod B eth0 (10.244.2.15)]
   ```
2. **Why does MTU matter on GCP with VXLAN?**
   - GCP VPC default MTU is `1460` bytes.
   - VXLAN adds `50` bytes of outer headers (`14B` outer L2 + `20B` outer IPv4 + `8B` UDP + `8B` VXLAN).
   - Therefore, `flannel.1` and Pod `eth0` interfaces must use an MTU of `1410` bytes (`1460 - 50`). If Pod MTU is misconfigured at `1500`, small `ping` packets succeed while large HTTP/TLS/gRPC payloads hang silently!

#### Week 2 Hands-On Deliverable
Deploy the diagnostic DaemonSet and workload lab, then run the automated packet path tracer:
```bash
kubectl apply -f kubernetes/networking/01-netshoot-debug-ds.yaml
kubectl apply -f kubernetes/networking/02-gateway-and-ingress-lab.yaml
./scripts/networking/trace-packet-path.sh
```

---

### Week 3 (Days 15–22): Services, `kube-proxy`, `EndpointSlices` & `CoreDNS`

#### Conceptual Check
1. **Does a Kubernetes `ClusterIP` exist on any network interface?**
   - No (`ip addr` will never show a `ClusterIP` in standard `iptables` mode). A `ClusterIP` is a **virtual IP (VIP)** that exists purely as netfilter `PREROUTING`/`OUTPUT` DNAT rules written by `kube-proxy`.
2. **How do `kube-proxy` `iptables` chains route traffic to 3 Pod backends?**
   - `PREROUTING` / `OUTPUT` → `KUBE-SERVICES` matches destination `ClusterIP:Port` → jumps to `KUBE-SVC-<HASH>`.
   - `KUBE-SVC-<HASH>` uses `--mode random --probability 0.33333333349` for replica 1 (`KUBE-SEP-<HASH1>`), `0.50000000000` for replica 2 (`KUBE-SEP-<HASH2>`), and falls through to replica 3 (`KUBE-SEP-<HASH3>`).
   - Each `KUBE-SEP-<HASH>` performs `-j DNAT --to-destination <PodIP>:<TargetPort>`.
   - `conntrack` records the 5-tuple so return packets from `<PodIP>` are reverse-translated back to `<ClusterIP>` before reaching the client socket!
3. **Why does `ndots:5` in `/etc/resolv.conf` cause 4x DNS query amplification for external domains?**
   - Because any hostname with fewer than 5 dots (like `api.openai.com`, which has 2 dots) is sequentially appended to every search domain (`<ns>.svc.cluster.local`, `svc.cluster.local`, `cluster.local`, `<gcp-internal>`) for both `A` and `AAAA` records before finally querying `api.openai.com.` as an FQDN!
   - **Fix**: Use trailing dots (`api.openai.com.`) in latency-sensitive configs or tune `dnsConfig.options: [{name: ndots, value: "2"}]`.

---

### Week 4 (Days 23–30): `Ingress`, `Gateway API`, `NetworkPolicies` & 10 Network Failure Drills

#### Conceptual Check
1. **Why does creating an `Ingress` or `HTTPRoute` object do nothing by itself?**
   - Because `Ingress` and `Gateway API` resources are declarative routing specifications stored in `etcd`. Without a running Ingress/Gateway controller (`ingress-nginx`, `envoy-gateway`, `cilium`) watching those API objects and programming a reverse proxy data plane, no socket is listening for external traffic.
2. **Important CNI Caveat for `NetworkPolicy`:**
   - Standard Flannel (`kube-flannel`) only provides L3/VXLAN connectivity and **does not enforce `NetworkPolicy` objects** unless paired with `Calico` (Canal), `kube-router`, or replaced with `Calico`/`Cilium`. If you apply a `NetworkPolicy` on a pure Flannel cluster without a policy controller, the API server stores the YAML in `etcd` and silently ignores it!

#### The 10 Network Failures You Must Reproduce & Resolve (Days 25–30)

| # | Failure Scenario | Layer | Root Cause & Verification Command |
| :---: | :--- | :---: | :--- |
| **1** | Cross-node Pod ping fails (`Destination Host Unreachable`) | L2/L3 CNI | Missing `/opt/cni/bin` plugin, stopped `kube-flannel`, or GCP firewall blocking UDP `:8472` ([Lab 01](../labs/lab-01-broken-cni.md)). |
| **2** | `ping` works, but large HTTP/TLS responses hang forever | L2 MTU | Pod/VXLAN MTU > `1410` on GCP `1460`-MTU VPC; verify with `ping -M do -s 1400 <pod-ip>`. |
| **3** | Service `ClusterIP` times out; direct `PodIP` works | L4 Service | Mismatched `spec.selector` on Service vs. Pod labels; `kubectl get endpointslices -l kubernetes.io/service-name=<svc>` shows empty endpoints ([Lab 08](../labs/lab-08-service-networking-and-dns.md)). |
| **4** | Service has Endpoints, but `Connection Refused` on `ClusterIP` | L4 Port | `targetPort` on Service does not match actual container listening port (`ss -tulpn` inside Pod netns). |
| **5** | Service works from host/same node, fails from other nodes | L4 Proxy | `kube-proxy` crashed or `iptables` `FORWARD` policy set to `DROP`. |
| **6** | Pod cannot resolve `<svc>.default.svc.cluster.local` | L7 DNS | `CoreDNS` pods down, bad `Corefile` upstream, or NetworkPolicy blocking UDP/TCP `:53` to `kube-dns`. |
| **7** | Intermittent 5s DNS timeouts under high load | L4 Conntrack | Linux UDP `conntrack` race condition or `nf_conntrack_max` table exhaustion; mitigate with `NodeLocal DNSCache`. |
| **8** | Readiness probe fails after config change; Service drops all traffic | L7 Lifecycle | Failing `readinessProbe` sets endpoint `ready: false` in `EndpointSlice`, removing DNAT target from `KUBE-SVC-*` ([Lab 10](../labs/lab-10-stuck-rollout-and-probes.md)). |
| **9** | `default-deny-all` `NetworkPolicy` breaks all outbound API calls | L3/L4 Policy | Missing egress rule for UDP/TCP `:53` (`kube-system` DNS) + target egress port ([`allow-dns-egress.yaml`](../../kubernetes/security/network-policies/allow-dns-egress.yaml)). |
| **10** | `Ingress` returns `502 Bad Gateway` / `504 Gateway Timeout` | L7 Gateway | Upstream Service points to wrong port, or streaming LLM response exceeds proxy `proxy-read-timeout` ([`03-llm-gateway.yaml`](../../kubernetes/ai-inference/03-llm-gateway.yaml)). |
