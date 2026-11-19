# Consistent IAM role naming across environments.
locals {
  name_prefix = "${var.app_name}-${var.environment}"
}
