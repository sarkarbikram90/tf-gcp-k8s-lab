# Lab 03: Certificate Expiration & PKI Renewal

## Objective
Diagnose and resolve node disconnections caused by expired control plane or kubelet client certificates.

---

## Failure Symptoms
1. Nodes transition to `NotReady`.
2. Kubelet logs report:
   ```text
   Failed to list *v1.Node: Unauthorized
   x509: certificate has expired or is not yet valid
   ```

---

## Diagnosis Workflow

### Step 1: Check Cluster Certificate Status
On any control plane node:
```bash
sudo kubeadm certs check-expiration
```
Inspect the expiration date of:
- `apiserver`
- `apiserver-kubelet-client`
- `front-proxy-client`
- `etcd-server`

### Step 2: Inspect Kubelet Client Certificate
```bash
sudo openssl x509 -in /var/lib/kubelet/pki/kubelet-client-current.pem -noout -dates
```

---

## Remediation

### Step 1: Renew Certificates via kubeadm
```bash
sudo kubeadm certs renew all
```

### Step 2: Restart Control Plane Static Pods
```bash
# Restart kubelet to pick up renewed certificates
sudo systemctl restart kubelet
```

### Step 3: Update User Kubeconfig
```bash
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

Verify that `kubectl get nodes` succeeds.
