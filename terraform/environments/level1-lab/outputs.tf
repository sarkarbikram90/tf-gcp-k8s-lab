output "control_plane_internal_ip" {
  description = "Internal IP address of the Control Plane VM"
  value       = module.compute.control_plane_ips["${var.cluster_name}-control-plane"]
}

output "worker_internal_ips" {
  description = "Internal IP addresses of the Worker VMs"
  value       = module.compute.worker_ips
}

output "iap_ssh_commands" {
  description = "Helper commands to SSH into each node securely through Identity-Aware Proxy (IAP)"
  value = {
    control_plane = "gcloud compute ssh ${var.cluster_name}-control-plane --zone=${var.zone} --tunnel-through-iap"
    worker_01     = "gcloud compute ssh ${var.cluster_name}-worker-01 --zone=${var.zone} --tunnel-through-iap"
    worker_02     = "gcloud compute ssh ${var.cluster_name}-worker-02 --zone=${var.zone} --tunnel-through-iap"
  }
}

output "next_steps" {
  description = "Instructions for bootstrapping Kubernetes with kubeadm"
  value       = <<-EOT
    Infrastructure provisioned successfully!

    Next steps:
    1. SSH to the Control Plane:
       gcloud compute ssh ${var.cluster_name}-control-plane --zone=${var.zone} --tunnel-through-iap

    2. Run node prerequisites on all 3 nodes (kubeadm/scripts/01-install-prereqs.sh).
    3. Initialize the Control Plane (kubeadm/scripts/02-init-control-plane.sh).
    4. Install CNI plugin (e.g. Flannel or Calico) so CoreDNS transitions to Running.
    5. Run the kubeadm join command on worker-01 and worker-02.
  EOT
}
