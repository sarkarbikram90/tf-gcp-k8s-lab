output "instances" {
  description = "Map of created Kubernetes node instances with network details"
  value = {
    for k, inst in google_compute_instance.node : k => {
      id          = inst.id
      name        = inst.name
      zone        = inst.zone
      internal_ip = inst.network_interface[0].network_ip
      external_ip = length(inst.network_interface[0].access_config) > 0 ? inst.network_interface[0].access_config[0].nat_ip : null
      self_link   = inst.self_link
    }
  }
}

output "control_plane_ips" {
  description = "Map of control plane node names to their internal IP addresses"
  value = {
    for k, inst in google_compute_instance.node :
    inst.name => inst.network_interface[0].network_ip
    if contains(inst.tags, "k8s-control-plane")
  }
}

output "worker_ips" {
  description = "Map of worker node names to their internal IP addresses"
  value = {
    for k, inst in google_compute_instance.node :
    inst.name => inst.network_interface[0].network_ip
    if contains(inst.tags, "k8s-worker")
  }
}
