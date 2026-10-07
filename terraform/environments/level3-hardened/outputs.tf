output "api_endpoint" {
  description = "Virtual IP and port of the Internal Load Balancer for the Kubernetes API server"
  value       = "${module.load_balancer.api_endpoint_ip}:6443"
}

output "kms_crypto_key_id" {
  description = "Cloud KMS CryptoKey ID for Kubernetes etcd secrets encryption provider"
  value       = var.enable_kms ? module.kms[0].crypto_key_id : null
}

output "secret_manager_secret_id" {
  description = "Secret Manager secret ID for external secret integration"
  value       = var.enable_secret_manager ? module.secret_manager[0].secret_id : null
}

output "control_plane_ips" {
  description = "Internal IP addresses of the 3 Control Plane nodes"
  value       = module.compute.control_plane_ips
}

output "worker_ips" {
  description = "Internal IP addresses of the 3 Worker nodes"
  value       = module.compute.worker_ips
}

output "iap_ssh_commands" {
  description = "Helper commands to SSH into each node via Identity-Aware Proxy (IAP)"
  value = {
    for k, inst in module.compute.instances :
    k => "gcloud compute ssh ${inst.name} --zone=${inst.zone} --tunnel-through-iap"
  }
}

output "hardening_summary" {
  description = "Overview of active security controls in Level 3"
  value       = <<-EOT
    ========================================================================
    LEVEL 3 SECURITY HARDENING APPLIED:
    ========================================================================
    1. Zero Public IPs: All nodes are RFC1918 private instances.
    2. Zero Public SSH: SSH allowed exclusively via IAP (35.235.240.0/20).
    3. Strict Network Segmentation:
       - etcd (2379-2380) isolated exclusively to Control Plane instances.
       - Kubelet (10250) callers restricted to Control Plane instances.
       - CNI (8472/179) and CoreDNS (53) strictly isolated.
    4. Cloud KMS Encryption at Rest:
       - Key: ${var.enable_kms ? module.kms[0].crypto_key_name : "disabled"}
    5. Google Secret Manager:
       - Secret: ${var.enable_secret_manager ? module.secret_manager[0].secret_id : "disabled"}
    6. OS Login & Least Privilege IAM Enforced.
    ========================================================================
  EOT
}
