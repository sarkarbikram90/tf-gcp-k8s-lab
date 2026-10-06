output "network_id" {
  description = "The ID of the VPC network"
  value       = google_compute_network.k8s_vpc.id
}

output "network_name" {
  description = "The name of the VPC network"
  value       = google_compute_network.k8s_vpc.name
}

output "subnet_id" {
  description = "The ID of the Kubernetes subnetwork"
  value       = google_compute_subnetwork.k8s_subnet.id
}

output "subnet_name" {
  description = "The name of the Kubernetes subnetwork"
  value       = google_compute_subnetwork.k8s_subnet.name
}

output "subnet_cidr" {
  description = "The CIDR block of the Kubernetes subnetwork"
  value       = google_compute_subnetwork.k8s_subnet.ip_cidr_range
}
