variable "project_id" {
  description = "The GCP Project ID where the Kubernetes infrastructure will be provisioned."
  type        = string
}

variable "region" {
  description = "The GCP region for the state storage bucket and resources."
  type        = string
  default     = "asia-south2"
}

variable "state_bucket_name" {
  description = "Globally unique name for the remote Terraform GCS state bucket."
  type        = string
}

variable "enable_apis" {
  description = "Whether to automatically enable necessary GCP APIs."
  type        = bool
  default     = true
}

variable "enable_wif" {
  description = "Whether to configure Workload Identity Federation for GitHub Actions CI/CD."
  type        = bool
  default     = true
}

variable "github_repository" {
  description = "The GitHub repository in 'owner/repo' format (e.g., 'sarkarbikram90/tf-gcp-k8s-lab') to restrict WIF impersonation."
  type        = string
  default     = ""
}
