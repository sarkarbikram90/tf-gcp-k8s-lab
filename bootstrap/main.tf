# ------------------------------------------------------------------------------
# 1. Required Google Cloud APIs
# ------------------------------------------------------------------------------
locals {
  required_services = [
    "compute.googleapis.com",
    "iam.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iamcredentials.googleapis.com",
    "sts.googleapis.com",
    "iap.googleapis.com"
  ]
}

resource "google_project_service" "enabled_apis" {
  for_each = var.enable_apis ? toset(local.required_services) : toset([])

  project            = var.project_id
  service            = each.key
  disable_on_destroy = false
}

# ------------------------------------------------------------------------------
# 2. Remote Terraform State GCS Bucket
# ------------------------------------------------------------------------------
resource "google_storage_bucket" "tf_state" {
  name          = var.state_bucket_name
  project       = var.project_id
  location      = var.region
  force_destroy = false

  # Prevent public exposure & enforce IAM-only access
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  # Protect state history and support recovery from accidental corruption
  versioning {
    enabled = true
  }

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      num_newer_versions         = 10
      days_since_noncurrent_time = 90
    }
  }

  depends_on = [google_project_service.enabled_apis]
}

# ------------------------------------------------------------------------------
# 3. Dedicated Terraform Deployer Service Account (Least Privilege)
# ------------------------------------------------------------------------------
resource "google_service_account" "tf_deployer" {
  account_id   = "terraform-deployer"
  display_name = "Terraform Deployer & CI/CD Service Account"
  description  = "Keyless identity used by local impersonation and GitHub Actions WIF"
  project      = var.project_id

  depends_on = [google_project_service.enabled_apis]
}

# Grant Terraform Deployer access to manage state in the GCS bucket
resource "google_storage_bucket_iam_member" "state_admin" {
  bucket = google_storage_bucket.tf_state.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.tf_deployer.email}"
}

# Project-level IAM permissions for infrastructure provisioning
locals {
  deployer_roles = [
    "roles/compute.networkAdmin",
    "roles/compute.instanceAdmin.v1",
    "roles/compute.securityAdmin",
    "roles/iam.serviceAccountUser"
  ]
}

resource "google_project_iam_member" "deployer_permissions" {
  for_each = toset(local.deployer_roles)

  project = var.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.tf_deployer.email}"

  depends_on = [google_project_service.enabled_apis]
}

# ------------------------------------------------------------------------------
# 4. Workload Identity Federation (WIF) for Keyless GitHub Actions CI/CD
# ------------------------------------------------------------------------------
resource "google_iam_workload_identity_pool" "github_pool" {
  count = var.enable_wif ? 1 : 0

  project                   = var.project_id
  workload_identity_pool_id = "github-actions-pool"
  display_name              = "GitHub Actions WIF Pool"
  description               = "Identity pool for GitHub Actions CI/CD workflows"

  depends_on = [google_project_service.enabled_apis]
}

resource "google_iam_workload_identity_pool_provider" "github_provider" {
  count = var.enable_wif ? 1 : 0

  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github_pool[0].workload_identity_pool_id
  workload_identity_pool_provider_id = "github-actions-provider"
  display_name                       = "GitHub Actions OIDC Provider"
  description                        = "OIDC Provider for github.com token exchange"

  attribute_mapping = {
    "google.subject"             = "assertion.sub"
    "attribute.actor"            = "assertion.actor"
    "attribute.repository"       = "assertion.repository"
    "attribute.repository_owner" = "assertion.repository_owner"
  }

  attribute_condition = var.github_repository != "" ? "assertion.repository == '${var.github_repository}'" : null

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# Allow GitHub Actions workflows in the specified repository to impersonate terraform-deployer
resource "google_service_account_iam_member" "wif_impersonation" {
  count = var.enable_wif && var.github_repository != "" ? 1 : 0

  service_account_id = google_service_account.tf_deployer.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github_pool[0].name}/attribute.repository/${var.github_repository}"
}
