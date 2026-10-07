variable "key_ring_name" {
  description = "Name of the Cloud KMS KeyRing"
  type        = string
  default     = "k8s-keyring"
}

variable "crypto_key_name" {
  description = "Name of the Cloud KMS CryptoKey used for Kubernetes secrets encryption"
  type        = string
  default     = "k8s-secrets-key"
}

variable "region" {
  description = "GCP location/region for the KMS KeyRing"
  type        = string
}

variable "service_account_email" {
  description = "Service account email to grant CryptoKey Encrypter/Decrypter permissions to"
  type        = string
  default     = null
}
