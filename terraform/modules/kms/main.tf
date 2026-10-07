resource "google_kms_key_ring" "keyring" {
  name     = var.key_ring_name
  location = var.region
}

resource "google_kms_crypto_key" "secrets_key" {
  name            = var.crypto_key_name
  key_ring        = google_kms_key_ring.keyring.id
  rotation_period = "7776000s" # 90 days automatic rotation

  version_template {
    algorithm        = "GOOGLE_SYMMETRIC_ENCRYPTION"
    protection_level = "SOFTWARE"
  }

  lifecycle {
    prevent_destroy = false
  }
}

# Grant the node / KMS plugin service account access to encrypt and decrypt secrets
resource "google_kms_crypto_key_iam_member" "encrypter_decrypter" {
  count = var.service_account_email != null ? 1 : 0

  crypto_key_id = google_kms_crypto_key.secrets_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${var.service_account_email}"
}
