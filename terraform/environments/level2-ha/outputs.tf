output "api_endpoint" {
  description = "Virtual IP and port of the Internal Load Balancer for the Kubernetes API server"
  value       = "${module.load_balancer.api_endpoint_ip}:6443"
}

output "control_plane_ips" {
  description = "Internal IP addresses of the 3 Control Plane nodes"
  value       = module.compute.control_plane_ips
}

output "worker_ips" {
  description = "Internal IP addresses of the Worker nodes"
  value       = module.compute.worker_ips
}

output "iap_ssh_commands" {
  description = "Helper commands to SSH into each node via Identity-Aware Proxy (IAP)"
  value = {
    for k, inst in module.compute.instances :
    k => "gcloud compute ssh ${inst.name} --zone=${inst.zone} --tunnel-through-iap"
  }
}

output "ha_bootstrap_guide" {
  description = "Next steps for bootstrapping the HA cluster with kubeadm"
  value       = <<-EOT
    Level 2 (HA) Infrastructure Provisioned!
    Control Plane Endpoint: ${module.load_balancer.api_endpoint_ip}:6443

    Bootstrapping Steps:
    1. Run kubeadm/scripts/01-install-prereqs.sh on ALL 6 nodes.
    2. Run kubeadm/scripts/04-init-ha-control-plane.sh on cp-01:
       Pass endpoint: ${module.load_balancer.api_endpoint_ip}:6443
    3. Run the generated 'join-control-plane' command on cp-02 and cp-03.
    4. Run the generated 'join-worker' command on worker-01, worker-02, and worker-03.
    5. Verify etcd quorum and API server health:
       kubectl get nodes -o wide
       kubectl get pods -n kube-system -l component=etcd
  EOT
}
