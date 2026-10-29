locals {

  account_id   = data.aws_caller_identity.current.account_id
  state_bucket = "${var.app_name}-${var.environment}-tfstate-${local.account_id}"
}
