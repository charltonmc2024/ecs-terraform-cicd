# vpc-origin.tf
#
# CloudFront VPC Origin fronting the internal ALB. This is the edge entry point that
# lets a CloudFront distribution (owned by 04-edge) reach the private, internal ALB
# without exposing it to the public internet.
#
# Dependency direction is strictly backend -> edge: this file references the ALB by
# ARN within the module and creates NO aws_cloudfront_distribution, no cache policy,
# and no origin-request policy (those belong to 04-edge). It references no 04-edge
# output. The ALB ARN is consumed internally here, so it is intentionally NOT exposed
# as a module output; only the VPC Origin id and the ALB DNS name are exported for
# 04-edge to attach the distribution origin (R4.1, R4.2, R4.3, R4.5, R12.4).

# Single VPC Origin targeting the internal ALB. In DEV the VPC Origin reaches the ALB
# over HTTP (origin_protocol_policy = "http-only") to match the HTTP listener in alb.tf
# (R4.4, R12.2): CloudFront terminates viewer TLS in 04-edge, and traffic from the VPC
# Origin to the ALB stays HTTP inside the VPC.
resource "aws_cloudfront_vpc_origin" "app" {
  vpc_origin_endpoint_config {
    name = "${local.name_prefix}-vpc-origin"
    arn  = aws_lb.app.arn

    # HTTP only: CloudFront connects to the internal ALB over HTTP on the private VPC
    # Origin path. http_port tracks var.alb_listener_port so the VPC Origin and the ALB
    # HTTP listener stay consistent. https_port and origin_ssl_protocols are required by
    # the resource schema; https_port is set to the conventional 443 placeholder and
    # carries no traffic while origin_protocol_policy is "http-only".
    http_port              = var.alb_listener_port
    https_port             = 443
    origin_protocol_policy = "http-only"

    origin_ssl_protocols {
      items    = ["TLSv1.2"]
      quantity = 1
    }
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-vpc-origin"
  })
}
