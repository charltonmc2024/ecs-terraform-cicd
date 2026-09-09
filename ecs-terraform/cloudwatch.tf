resource "aws_cloudwatch_log_group" "ecs_logs" {
  name              = "/ecs/${var.environment}-${var.app_name}-ecs-logs"
  retention_in_days = 1
  tags = {
    name = "${var.environment}-${var.app_name}-ecs-logs"

  }

}