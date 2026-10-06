resource "google_service_account" "k8s_node" {
  account_id   = var.service_account_id
  display_name = "Kubernetes Node Runtime Service Account"
  description  = "Least-privilege service account attached to Kubernetes VMs"
  project      = var.project_id
}

locals {
  node_roles = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter"
  ]
}

resource "google_project_iam_member" "node_roles" {
  for_each = toset(local.node_roles)

  project = var.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.k8s_node.email}"
}
