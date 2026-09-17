resource "aws_ecs_cluster" "ecs_cluster" {
  name = "${var.app_name}-${var.environment}-ecs-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name = "${var.environment}-${var.app_name}-ecs-cluster"
  }

}