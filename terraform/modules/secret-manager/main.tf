resource "google_secret_manager_secret" "secret" {
  secret_id = var.secret_id

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "secret_val" {
  secret      = google_secret_manager_secret.secret.id
  secret_data = var.secret_data
}

# Grant secretAccessor role to the Kubernetes node / workload runtime identity
resource "google_secret_manager_secret_iam_member" "accessor" {
  count = var.service_account_email != null ? 1 : 0

  secret_id = google_secret_manager_secret.secret.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.service_account_email}"
}
