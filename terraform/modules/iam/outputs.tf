output "service_account_email" {
  description = "The email address of the Kubernetes node runtime service account"
  value       = google_service_account.k8s_node.email
}

output "service_account_id" {
  description = "The ID of the Kubernetes node runtime service account"
  value       = google_service_account.k8s_node.id
}
