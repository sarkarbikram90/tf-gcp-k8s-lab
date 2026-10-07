output "secret_id" {
  description = "The ID of the Secret Manager secret"
  value       = google_secret_manager_secret.secret.secret_id
}

output "secret_name" {
  description = "The resource name of the Secret Manager secret"
  value       = google_secret_manager_secret.secret.name
}
