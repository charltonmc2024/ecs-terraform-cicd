resource "aws_ecs_cluster" "ecs_cluster" {
  name = "${var.environment}-${var.app_name}-ecs-cluster"

  tags = {
    Name = "${var.environment}-${var.app_name}-ecs-cluster"
  }

}