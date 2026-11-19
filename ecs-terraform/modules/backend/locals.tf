
locals {
  # Single naming base for every resource name in this module.
  name_prefix = "${var.app_name}-${var.environment}"

  # Inject application secrets only when their ARNs are configured.
  # The ECS execution role retrieves these secrets at task startup.
  container_secrets = concat(
    var.app_secret_arn == null ? [] : [
      {
        name      = "MONGODB_URL"
        valueFrom = var.app_secret_arn
      }
    ],
    var.staff_admin_secret_arn == null ? [] : [
      {
        name      = "STAFF_ADMIN_MONGO_URL"
        valueFrom = var.staff_admin_secret_arn
      }
    ]
  )

  # Collect configured application secret ARNs.
  # Supports both app_secret_arn and staff_admin_secret_arn.
  # Null or empty values are excluded, and duplicates removed.
  #
  # These ARNs are used for ECS task definition configuration.
  # IAM policies and attachments are managed separately
  # by the administrator-owned IAM configuration.
  #
  # ECS execution roles require secretsmanager:GetSecretValue
  # permissions for the configured Secrets Manager ARNs.
  # SSM Parameter Store access requires separate permissions.
  mongo_secret_arns = distinct(compact([
    var.app_secret_arn,
    var.staff_admin_secret_arn
  ]))
}
