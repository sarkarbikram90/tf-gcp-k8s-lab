# Step 0: Remote State & Identity Bootstrap

This directory provisions the foundational cloud infrastructure required before deploying the Kubernetes environments:

1. **GCS Remote State Bucket**:
   - Uniform bucket-level access and public access prevention enforced.
   - Object versioning enabled to prevent state corruption and allow rollback.
2. **Dedicated Deployer Service Account**:
   - Least-privilege IAM service account (`terraform-deployer`).
   - Used for both local impersonation (keyless) and automated CI/CD pipelines.
3. **Workload Identity Federation (WIF)**:
   - Sets up Google Cloud OIDC trust with GitHub Actions.
   - Eliminates the need for long-lived service account JSON keys in GitHub secrets.
4. **Google Cloud APIs**:
   - Automatically enables necessary APIs (`compute`, `iam`, `iap`, `sts`, `iamcredentials`).

## Usage

```bash
cd bootstrap

# 1. Authenticate locally with Application Default Credentials
gcloud auth application-default login
gcloud config set project YOUR_PROJECT_ID

# 2. Configure variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your GCP project ID and bucket name

# 3. Initialize and Apply
terraform init
terraform plan
terraform apply
```

After `terraform apply` finishes, note the outputs:
- `state_bucket_name`: Used to configure `backend.hcl` in `terraform/environments/level1-lab`.
- `wif_provider_name`: Used in GitHub Actions workflows.
