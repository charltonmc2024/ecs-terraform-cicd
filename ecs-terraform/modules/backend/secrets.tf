# secrets.tf
#
# Secrets policy (R7):
#
#   - No secret VALUE ever lives in Terraform source, tfvars, the Dockerfile, the
#     Jenkinsfile, or any committed file. This module only references an externally
#     managed secret by ARN; it never creates the secret or its value.
#   - This module creates NO aws_secretsmanager_secret and no secret-value resource.
#     The secret is owned outside this stack (Secrets Manager or SSM Parameter Store)
#     and supplied to the module as var.app_secret_arn (marked sensitive, no default
#     secret value) (R7.1, R7.4).
#   - In DEV, var.app_secret_arn defaults to null, so every resource below is
#     count-gated to zero. The default DEV plan therefore contains ZERO secret
#     resources and the task definition declares no secrets entry (R7.3).
#   - When a concrete ARN is supplied, the MongoDB Atlas connection URI is injected
#     through the task definition `secrets` block as MONGODB_URL (wired in ecs.tf via
#     local.container_secrets, which is empty when var.app_secret_arn == null), and
#     the Execution_Role is granted read access scoped to EXACTLY that one ARN — no
#     wildcard resource (R7.2).
#
# The Execution_Role (not the Task_Role) reads the secret because the ECS agent
# resolves task-definition `secrets` at task start, before the application runs.

data "aws_iam_policy_document" "execution_secret" {
  count = length(local.mongo_secret_arns) > 0 ? 1 : 0

  statement {
    sid    = "ReadMongoSecrets"
    effect = "Allow"

    actions = [
      "secretsmanager:GetSecretValue"
    ]

    resources = local.mongo_secret_arns
  }
}

resource "aws_iam_policy" "execution_secret" {
  count = length(local.mongo_secret_arns) > 0 ? 1 : 0

  name        = "${local.name_prefix}-ecs-execution-secret"
  description = "Scoped read access to exactly the injected application secret ARN for the ${local.name_prefix} ECS execution role."
  policy      = data.aws_iam_policy_document.execution_secret[0].json

  tags = merge(var.tags, { Name = "${local.name_prefix}-ecs-execution-secret" })
}

resource "aws_iam_role_policy_attachment" "execution_secret" {
  count = length(local.mongo_secret_arns) > 0 ? 1 : 0

  role       = aws_iam_role.execution.name
  policy_arn = aws_iam_policy.execution_secret[0].arn
}
