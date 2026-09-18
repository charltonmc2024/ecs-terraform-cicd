resource "aws_cloudwatch_log_group" "ecs_logs" {
  name              = "/ecs/${local.name_prefix}-ecs-logs"
  retention_in_days = 1
  tags = {
    name = "${var.environment}-${var.app_name}-ecs-logs"

  }

}