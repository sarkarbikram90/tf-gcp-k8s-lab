# Lab 04: Node DiskPressure & Storage Reclamation

## Objective
Diagnose a node marked with `DiskPressure`, identify the cause of root volume exhaustion, and restore normal scheduling.

---

## Failure Symptoms
1. `kubectl get nodes` shows node condition:
   ```text
   Conditions:
     Type             Status
     DiskPressure     True
   ```
2. Pods scheduled on the node are evicted with status `Evicted`.

---

## Diagnosis Workflow

### Step 1: Check Node Conditions
```bash
kubectl describe node <node-name> | grep -A 5 Conditions
```

### Step 2: Check Disk Usage on the Affected Node
SSH to the node:
```bash
df -h /
```

### Step 3: Inspect Container Image Cache & Logs
```bash
# Check size of containerd image cache:
sudo du -sh /var/lib/containerd/

# Check size of system logs:
sudo du -sh /var/log/
```

---

## Remediation

### Step 1: Prune Unused Container Images
```bash
sudo crictl rmi --prune
```

### Step 2: Clean System Journals
```bash
sudo journalctl --vacuum-time=2d
```

### Step 3: Verify Node Recovers
```bash
kubectl describe node <node-name> | grep DiskPressure
# Should transition to DiskPressure: False
```
