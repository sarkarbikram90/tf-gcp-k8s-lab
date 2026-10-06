variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "service_account_id" {
  description = "Identifier for the Kubernetes node service account"
  type        = string
  default     = "k8s-node-sa"
}
