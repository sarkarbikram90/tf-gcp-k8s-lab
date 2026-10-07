variable "secret_id" {
  description = "Identifier for the secret in Google Cloud Secret Manager"
  type        = string
  default     = "k8s-app-database-credentials"
}

variable "secret_data" {
  description = "Secret payload to store in Secret Manager"
  type        = string
  default     = "{\"username\":\"db_admin\",\"password\":\"super-secret-password-from-gcp-secret-manager\"}"
}

variable "service_account_email" {
  description = "Service account granted secretAccessor permission"
  type        = string
  default     = null
}
