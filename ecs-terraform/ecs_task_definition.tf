# ---------------------------------------------------------------------------
# ECS Task Definition
#
# Secrets are injected at container launch via ECS secrets — the value is
# pulled from AWS Secrets Manager by the task execution role and set as an
# environment variable inside the container. The secret value never appears
# in Terraform state or task definition JSON in plaintext.
# ---------------------------------------------------------------------------

# Look up the exact ARN of the MongoDB secret (includes the AWS-generated suffix).
data "aws_secretsmanager_secret" "mongo_details" {
  name = "${var.app_name}/${var.environment}/mongo-details"
}

resource "aws_ecs_task_definition" "ecs_task" {
  skip_destroy             = false
  family                   = "${local.name_prefix}-ecs-task"
  cpu                      = var.ecs_task_cpu
  memory                   = var.ecs_task_memory
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]

  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn      = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name  = "${local.name_prefix}-container"
      image = "${aws_ecr_repository.ecr_repo.repository_url}:latest"

      portMappings = [
        {
          containerPort = var.container_port
          hostPort      = var.container_port
          protocol      = "tcp"
        }
      ]

      # Inject the MongoDB connection string from Secrets Manager.
      # ECS resolves the secret at launch — value is never in plaintext here.
      secrets = [
        {
          name      = "MONGO_DETAILS"
          valueFrom = data.aws_secretsmanager_secret.mongo_details.arn
        }
      ]

      environment = [
        {
          name  = "DB_NAME"
          value = "eruditiontx_db"
        },
        {
          name  = "PORT"
          value = tostring(var.container_port)
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs_logs.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }

      essential = true
    }
  ])

  tags = {
    Name = "${local.name_prefix}-ecs-task"
  }
}
