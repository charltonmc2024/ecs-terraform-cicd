# iam.tf
#
# Two distinct, least-privilege IAM roles back the ECS Fargate task (R6.1):
#   - Execution_Role: assumed by the ECS agent to pull the image from ECR, write
#     container logs to CloudWatch, and (when app_secret_arn is set) read the single
#     injected secret. Uses the AWS-managed execution policy plus, optionally, the
#     scoped secret-read policy in secrets.tf (R6.2).
#   - Task_Role: assumed by the running application container as its runtime identity.
#     The application database is MongoDB Atlas (external managed service), reached
#     over the network using the connection URI injected from Secrets Manager, so the
#     task role needs NO AWS data-plane permissions and carries no inline policy.
#
# No IAM user and no long-lived access key are created; the ECS service principal
# assumes these roles via STS at task start, so no AWS credentials are embedded
# anywhere (R6.4). Trust is restricted to the ECS task service principal only (R6.5).

# Trust policy shared by both roles: only the ECS task runtime principal may assume
# them via sts:AssumeRole. Scoping the principal to ecs-tasks.amazonaws.com keeps the
# roles unusable by any other service or account (R6.5).
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
  name               = "${local.name_prefix}-ecs-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json

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
  name               = "${local.name_prefix}-ecs-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json

  tags = merge(var.tags, { Name = "${local.name_prefix}-ecs-task" })
}
