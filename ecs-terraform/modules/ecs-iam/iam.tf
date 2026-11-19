# iam.tf
#
# Administrator-managed IAM roles for ECS Fargate.
#
# Four roles are defined:
#   - Next.js execution role: ECR image pulls and CloudWatch logging.
#   - Next.js task role: application runtime identity.
#   - FastAPI execution role: ECR, logging, and separately configured secrets.
#   - FastAPI task role: application runtime identity.
#
# IAM roles and policy attachments are managed separately from the
# ECS infrastructure deployment.
#
# Each role uses an administrator-configured permissions boundary.
# Trust is restricted to ecs-tasks.amazonaws.com with AWS source
# account and source ARN conditions.
#
# No IAM users or long-lived access keys are created.
#
# ECS task definitions reference these roles through IAM data sources.
#
data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_iam_policy_document" "ecs_assume_role" {
  statement {
    sid     = "EcsTasksAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values = [
        "arn:${data.aws_partition.current.partition}:ecs:*:${data.aws_caller_identity.current.account_id}:*"
      ]
    }
  }
}

# --- Execution_Role (R6.1, R6.2) ---
# The ECS agent uses this role to pull the image and ship logs; the application does
# not use it. It carries only the AWS-managed execution policy, never AdministratorAccess.
resource "aws_iam_role" "execution" {
  name                 = "${local.name_prefix}-ecs-execution"
  assume_role_policy   = data.aws_iam_policy_document.ecs_assume_role.json
  permissions_boundary = var.ecs_permissions_boundary_arn

  tags = merge(var.tags, { Name = "${local.name_prefix}-ecs-execution" })
}

# AmazonECSTaskExecutionRolePolicy grants exactly ECR image pull and CloudWatch Logs
# writes required at task start. Attaching the AWS-managed policy avoids hand-rolling
# (and drifting from) those permissions. No AdministratorAccess is attached (R6.2).
resource "aws_iam_role_policy_attachment" "execution_managed" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# --- Task_Role (R6.1, R6.3) ---
# The running application container assumes this role as its runtime identity. The
# application database is MongoDB Atlas (an external managed service reached over the
# network, not an AWS API), so the task role requires NO AWS data-plane permissions
# and carries no inline or attached policy. It never holds AdministratorAccess or
# wildcard permissions. Reading the MongoDB connection secret is handled by the
# EXECUTION role at task start (see secrets.tf), not by this role. If the application
# later needs a specific AWS API (e.g. S3 object storage), a scoped policy would be
# attached here at that time.
resource "aws_iam_role" "task" {
  name                 = "${local.name_prefix}-ecs-task"
  assume_role_policy   = data.aws_iam_policy_document.ecs_assume_role.json
  permissions_boundary = var.ecs_permissions_boundary_arn

  tags = merge(var.tags, { Name = "${local.name_prefix}-ecs-task" })
}


# FastAPI ECS execution role.
# Used by ECS to pull images, write logs, and retrieve configured secrets.
resource "aws_iam_role" "api_execution" {
  name                 = "${local.name_prefix}-api-execution"
  assume_role_policy   = data.aws_iam_policy_document.ecs_assume_role.json
  permissions_boundary = var.ecs_permissions_boundary_arn

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-api-execution"
  })
}

resource "aws_iam_role_policy_attachment" "api_execution_managed" {
  role       = aws_iam_role.api_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# FastAPI runtime role.
# No AWS data-plane permissions are required for MongoDB Atlas access.
resource "aws_iam_role" "api_task" {
  name                 = "${local.name_prefix}-api-task"
  assume_role_policy   = data.aws_iam_policy_document.ecs_assume_role.json
  permissions_boundary = var.ecs_permissions_boundary_arn

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-api-task"
  })
}
