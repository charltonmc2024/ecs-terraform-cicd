resource "aws_ecs_task_definition" "ecs_task" {

  skip_destroy             = false
  family                   = "${var.environment}-${var.app_name}-ecs-task"
  cpu                      = var.ecs_task_cpu
  memory                   = var.ecs_task_memory
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]

  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn
  container_definitions = jsonencode([{
    name  = "${var.environment}-${var.app_name}-container"
    image = "${aws_ecr_repository.ecr_repo.repository_url}:latest"
    portMappings = [{
      containerPort = var.container_port
      hostPort      = var.container_port
      protocol      = "tcp"
    }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.ecs_logs.name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "ecs"
      }
    }

  }])
  tags = {
    "name" = "${var.environment}-${var.app_name}-ecs-task"
  }
}
