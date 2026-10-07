output "key_ring_name" {
  description = "Name of the created KMS KeyRing"
  value       = google_kms_key_ring.keyring.name
}

output "key_ring_id" {
  description = "Identifier of the created KMS KeyRing"
  value       = google_kms_key_ring.keyring.id
}

output "crypto_key_name" {
  description = "Name of the KMS CryptoKey"
  value       = google_kms_crypto_key.secrets_key.name
}

output "crypto_key_id" {
  description = "Full resource ID of the KMS CryptoKey for KMS encryption provider plugin"
  value       = google_kms_crypto_key.secrets_key.id
}
