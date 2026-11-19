# Administrator-managed ECS IAM roles.
# This Terraform root is separate from Jenkins deployments.

module "ecs_iam" {
  source = "../../../ecs-terraform/modules/ecs-iam"

  app_name    = var.app_name
  environment = var.environment
  tags        = var.tags

  ecs_permissions_boundary_arn = var.ecs_permissions_boundary_arn
  api_execution_secret_policy_arn = "arn:aws:iam::691778449106:policy/eruditiontx-app-ecs-dev-api-execution-secret"

  api_mongodb_secret_arn = var.api_mongodb_secret_arn
  api_key_secret_arn     = var.api_key_secret_arn
}
