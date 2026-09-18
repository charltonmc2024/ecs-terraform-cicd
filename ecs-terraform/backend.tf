# ---------------------------------------------------------------------------
# Terraform Remote State Backend
#
# Values are passed at init time via -backend-config to avoid hardcoding.
# The S3 bucket and DynamoDB table are created by:
#   ecs-terraform/bootstrap/
#
# Setup steps (one-time):
#   1. cd ecs-terraform/bootstrap && terraform init && terraform apply
#   2. cd ../
#   3. terraform init -backend-config=backend.config
#      (Terraform will offer to migrate any existing local state — type: yes)
#
# For CI/CD, pass backend config via environment variables or the
# -backend-config flag in the buildspec.
# ---------------------------------------------------------------------------

terraform {
  backend "s3" {}
}
