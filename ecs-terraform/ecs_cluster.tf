resource "aws_ecs_cluster" "ecs_cluster" {
  name = "${local.name_prefix}-ecs-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name = "${var.environment}-${var.app_name}-ecs-cluster"
  }

}