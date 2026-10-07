output "api_endpoint_ip" {
  description = "Internal Virtual IP (VIP) of the Kubernetes API server load balancer"
  value       = google_compute_forwarding_rule.k8s_api.ip_address
}

output "forwarding_rule_id" {
  description = "The ID of the internal load balancer forwarding rule"
  value       = google_compute_forwarding_rule.k8s_api.id
}

output "backend_service_id" {
  description = "The ID of the regional backend service"
  value       = google_compute_region_backend_service.k8s_api.id
}
