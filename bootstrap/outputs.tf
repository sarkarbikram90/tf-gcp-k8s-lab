output "state_bucket_name" {
  description = "Name of the remote state GCS bucket to configure in backend.hcl"
  value       = google_storage_bucket.tf_state.name
}

output "deployer_service_account_email" {
  description = "Email of the dedicated Terraform deployer service account"
  value       = google_service_account.tf_deployer.email
}

output "wif_provider_name" {
  description = "Resource name of the Workload Identity Provider for GitHub Actions"
  value       = var.enable_wif ? google_iam_workload_identity_pool_provider.github_provider[0].name : null
}

output "backend_config_snippet" {
  description = "Example backend.hcl snippet for environment state configuration"
  value       = <<-EOT
    bucket = "${google_storage_bucket.tf_state.name}"
    prefix = "terraform/state/level1-lab"
  EOT
}
