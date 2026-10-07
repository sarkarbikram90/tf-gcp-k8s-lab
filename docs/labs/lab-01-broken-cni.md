# Lab 01: Broken CNI & Network Troubleshooting

## Objective
Diagnose and repair a cluster where Pods cannot acquire IP addresses and CoreDNS is stuck in `ContainerCreating` or `Pending`.

---

## Failure Symptoms
1. `kubectl get pods -A` reveals CoreDNS pods stuck in `ContainerCreating` or `CrashLoopBackOff`.
2. Inspecting the pod with `kubectl describe pod <coredns-pod> -n kube-system` shows:
   ```text
   Warning  FailedCreatePodSandBox  ...  networkPlugin cni failed to set up pod ... network: open /run/flannel/subnet.env: no such file or directory
   ```
3. New workloads never schedule with valid IP addresses.

---

## Diagnosis Workflow

### Step 1: Check Node Status & Pod Network
```bash
kubectl get nodes
```
If nodes show `NotReady`, the kubelet network plugin is uninitialized.

### Step 2: Inspect Kubelet Logs
On the affected node:
```bash
journalctl -u kubelet -e --no-pager | grep -i cni
```
Look for errors loading configurations from `/etc/cni/net.d/`.

### Step 3: Check Container Runtime Status
```bash
sudo crictl pods
sudo crictl ps -a
```

---

## Remediation
1. Verify `/etc/cni/net.d/` contains valid CNI configuration.
2. Ensure kernel modules `overlay` and `br_netfilter` are loaded:
   ```bash
   lsmod | grep -E 'overlay|br_netfilter'
   ```
3. Re-apply the CNI daemonset:
   ```bash
   kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
   ```
4. Verify CoreDNS recovers to `Running`:
   ```bash
   kubectl get pods -n kube-system -l k8s-app=kube-dns -w
   ```
