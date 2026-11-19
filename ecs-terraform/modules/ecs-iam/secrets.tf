
# secrets.tf
#
# Secret values are managed externally in AWS Secrets Manager.
# This module references existing secret ARNs and an administrator-managed
# IAM policy. It manages the FastAPI execution role's policy attachment
# but does not create secrets, secret values, or IAM policies.
#
# ECS execution roles retrieve injected secrets at task startup.

# FastAPI Secrets Manager access.
locals {
  api_secret_arns = compact([
    var.api_mongodb_secret_arn,
    var.api_key_secret_arn
  ])
}

# Attach the administrator-managed FastAPI secret policy.
resource "aws_iam_role_policy_attachment" "api_execution_secret" {
  count = nonsensitive(length(local.api_secret_arns) > 0) ? 1 : 0

  role       = aws_iam_role.api_execution.name
  policy_arn = var.api_execution_secret_policy_arn
}
