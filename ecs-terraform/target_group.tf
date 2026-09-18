resource "aws_lb_target_group" "ecs_tg" {
  name        = "${local.name_prefix}-tg"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = var.health_check_path
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
    matcher             = "200-399"
    port                = "traffic-port"
    protocol            = "HTTP"
  }

  deregistration_delay = 30

  tags = {

    Name = "${local.name_prefix}-tg"

  }
}
