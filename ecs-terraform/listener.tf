# ---------------------------------------------------------------------------
# ALB Listeners
#
# Port 80  — redirects all HTTP traffic to HTTPS (301).
# Port 443 — HTTPS listener forwards to the ECS target group.
# ---------------------------------------------------------------------------

# HTTP → HTTPS redirect
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.ecs_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# HTTPS listener — forwards to ECS target group.
# Depends on certificate validation so the cert is issued before the listener tries to attach it.
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.ecs_alb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.alb.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ecs_tg.arn
  }

  depends_on = [aws_acm_certificate_validation.alb]
}
