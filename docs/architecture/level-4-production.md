# Level 4: Platform Engineering & Production Operations

## Overview
Level 4 introduces complete Day-2 operational automation, enterprise CI/CD, disaster recovery, and deep observability across both infrastructure and cluster layers.

## Key Capabilities
1. **Keyless CI/CD with Workload Identity Federation (WIF)**:
   - GitHub Actions uses OpenID Connect (OIDC) to exchange short-lived federated tokens with Google Cloud.
   - Zero static service account JSON keys stored in GitHub repository secrets.
   - Pull request validation pipeline (`terraform fmt`, `terraform validate`, `tflint`, `gitleaks`, `trivy`, `terraform plan`).
2. **Disaster Recovery & etcd Backup/Restore**:
   - Automated scheduled etcd snapshots written directly to an encrypted Google Cloud Storage bucket with object lifecycle retention.
   - Runbook-tested restore procedure validating cluster state recovery in under 15 minutes.
3. **Full-Stack Observability**:
   - Prometheus and Alertmanager monitoring control-plane health (`kube-apiserver` latency, etcd leader elections, kubelet heartbeats).
   - Grafana dashboards visualizing cluster resource allocation, network throughput, and node saturation.
   - Centralized container logs streaming to Cloud Logging via Fluent Bit or OpenTelemetry collector.
4. **Automated Rolling Upgrades**:
   - Blue/green or sequential in-place rolling upgrade procedures (`kubeadm upgrade apply`, node drains, kubelet binary updates).
5. **SRE Failure-Injection & Troubleshooting Laboratory**:
   - Automated 10-scenario fault injection and verification harness ([`scripts/troubleshooting/sre-lab-runner.sh`](../../scripts/troubleshooting/sre-lab-runner.sh)) covering CNI/CoreDNS, etcd quorum, PKI expiry, `DiskPressure`, `CrashLoopBackOff`/`ImagePullBackOff`, `Pending` scheduling predicates, `OOMKilled` cgroups, Service/`NetworkPolicy` blackholes, `PVC` binding, and stuck rollouts/`PDB` deadlocks.
   - Supports blind 25-minute random on-call drills (`random`) and structured post-mortems ([`docs/labs/incident-report-template.md`](../labs/incident-report-template.md)).
