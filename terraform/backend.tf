# Remote state backend — S3.
#
# Backend block is intentionally partial: pass concrete values at `terraform init`
# time so secrets and bucket names don't land in version control. Example:
#
#   terraform init \
#     -backend-config="bucket=$AWS_TF_STATE_BUCKET" \
#     -backend-config="key=lightspeed-patching.tfstate" \
#     -backend-config="region=$AWS_DEFAULT_REGION"
#
# The S3 bucket must exist before `init`. One-time bootstrap:
#
#   aws s3 mb "s3://lightspeed-patching-tfstate-<your-initials>" \
#     --region us-east-1
#
# For local smoke testing only, comment out the backend block below and
# state will live in `terraform.tfstate` (gitignored).

terraform {
  backend "s3" {
    # values supplied via `-backend-config=...` at init time
  }
}
