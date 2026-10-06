# ------------------------------------------------------------------------------
# Remote State Configuration
# ------------------------------------------------------------------------------
# To initialize remote state using the GCS bucket provisioned by bootstrap/:
#   cp backend.hcl.example backend.hcl  # fill in bucket name
#   terraform init -backend-config=backend.hcl
#
# If running locally for testing without a remote bucket, comment out this block.
terraform {
  backend "gcs" {}
}
