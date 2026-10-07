# Kubernetes Rolling Upgrade Runbook

This runbook covers how to perform sequential, zero-downtime rolling upgrades on a self-managed multi-master Kubernetes cluster using `kubeadm`.

---

## 1. Upgrade Principles
1. **Never skip minor versions**: (e.g. `1.30` → `1.31` → `1.32`, never `1.30` → `1.32`).
2. **Upgrade sequence**:
   - Primary Control Plane (`cp-01`)
   - Secondary Control Planes (`cp-02`, `cp-03`)
   - Worker Nodes (`worker-01`, `worker-02`, etc.) sequentially.
3. **Always take an etcd backup** prior to initiating any cluster upgrade.

---

## 2. Step 0: Take Pre-Upgrade etcd Snapshot
```bash
sudo ./scripts/disaster-recovery/etcd-backup.sh gs://my-k8s-backups
```

---

## 3. Step 1: Upgrade Primary Control Plane (`cp-01`)

1. **Check Available Versions**:
   ```bash
   sudo apt update
   sudo apt-cache madison kubeadm | head -n 5
   ```

2. **Upgrade kubeadm**:
   ```bash
   sudo apt-mark unhold kubeadm
   sudo apt-get install -y --allow-change-held-packages kubeadm=1.31.1-1.1
   sudo apt-mark hold kubeadm
   ```

3. **Plan and Apply Upgrade**:
   ```bash
   sudo kubeadm upgrade plan
   sudo kubeadm upgrade apply v1.31.1
   ```

4. **Drain Node**:
   ```bash
   kubectl drain k8s-ha-cp-01 --ignore-daemonsets --delete-emptydir-data
   ```

5. **Upgrade Kubelet & Kubectl**:
   ```bash
   sudo apt-mark unhold kubelet kubectl
   sudo apt-get install -y --allow-change-held-packages kubelet=1.31.1-1.1 kubectl=1.31.1-1.1
   sudo apt-mark hold kubelet kubectl
   sudo systemctl daemon-reload
   sudo systemctl restart kubelet
   ```

6. **Uncordon Node**:
   ```bash
   kubectl uncordon k8s-ha-cp-01
   ```

---

## 4. Step 2: Upgrade Secondary Control Planes (`cp-02`, `cp-03`)

Repeat on each secondary control plane sequentially:
1. Upgrade `kubeadm`:
   ```bash
   sudo apt-mark unhold kubeadm
   sudo apt-get install -y --allow-change-held-packages kubeadm=1.31.1-1.1
   sudo apt-mark hold kubeadm
   ```
2. Run upgrade node:
   ```bash
   sudo kubeadm upgrade node
   ```
3. Drain, upgrade `kubelet` & `kubectl`, restart, and uncordon.

---

## 5. Step 3: Upgrade Worker Nodes

Repeat sequentially on each worker node:
```bash
# 1. Drain worker from control plane:
kubectl drain k8s-ha-worker-01 --ignore-daemonsets --delete-emptydir-data

# 2. On worker node:
sudo apt-mark unhold kubeadm
sudo apt-get install -y --allow-change-held-packages kubeadm=1.31.1-1.1
sudo apt-mark hold kubeadm

sudo kubeadm upgrade node

sudo apt-mark unhold kubelet kubectl
sudo apt-get install -y --allow-change-held-packages kubelet=1.31.1-1.1 kubectl=1.31.1-1.1
sudo apt-mark hold kubelet kubectl

sudo systemctl daemon-reload
sudo systemctl restart kubelet

# 3. Uncordon from control plane:
kubectl uncordon k8s-ha-worker-01
```
