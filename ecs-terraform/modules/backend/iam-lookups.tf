# Existing ECS IAM roles are managed by the administrator-owned
# Terraform root at iam-policies/ecs-roles/dev/.

data "aws_iam_role" "execution" {
  name = "${local.name_prefix}-ecs-execution"
}

data "aws_iam_role" "task" {
  name = "${local.name_prefix}-ecs-task"
}

data "aws_iam_role" "api_execution" {
  name = "${local.name_prefix}-api-execution"
}

data "aws_iam_role" "api_task" {
  name = "${local.name_prefix}-api-task"
}
