# cloudfront.tf
#
# Terraform loads every .tf file in this directory as one module, so file
# separation is purely for readability (conventions steering). Following the
# 02-data and 03-backend pattern, the module's `terraform {}` version block
# lives at the top of this main file rather than in a separate versions.tf,
# keeping organizational-only files out of the module. All `locals` (including
# name_prefix) live in locals.tf.
#
# This module declares NO `provider` block and NO `backend` block: it inherits
# the AWS provider (and the `aws.us_east_1` alias, available for a future custom
# ACM certificate) from the Dev_Root at ecs-terraform/envs/dev/.

terraform {
  required_version = "~> 1.16.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.67.0, < 7.0.0"
    }
  }
}

# Task 5.1 — Edge-owned CloudFront VPC Origin fronting the internal ALB.
#
# The VPC Origin is a CloudFront-specific integration resource owned by this edge
# module (not by 03-backend). Its endpoint targets the internal ALB by ARN via
# var.alb_arn (consumed from module.backend.alb_arn); the ALB stays private and
# no ALB or ECS resource is created here. The hop is HTTP (origin_protocol_policy
# = "http-only") on var.alb_http_port, matching the internal ALB's HTTP listener.
#
# https_port and the origin_ssl_protocols block are REQUIRED by the AWS provider
# schema (~> 6.62) even under http-only, so both are set; they carry no traffic
# while HTTP-only is selected.
resource "aws_cloudfront_vpc_origin" "api" {
  vpc_origin_endpoint_config {
    name                   = "${local.name_prefix}-api"
    arn                    = var.alb_arn
    http_port              = var.alb_http_port
    https_port             = 443
    origin_protocol_policy = "http-only"

    origin_ssl_protocols {
      items    = ["TLSv1.2"]
      quantity = 1
    }
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-api-vpc-origin"
  })
}

# Task 5.2 — Managed CloudFront policies.
# Disable caching for dynamic Next.js and FastAPI responses.
# Forward viewer request data except the Host header.
data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_origin_request_policy" "all_viewer_except_host" {
  name = "Managed-AllViewerExceptHostHeader"
}

data "aws_cloudfront_response_headers_policy" "security" {
  name = "Managed-SecurityHeadersPolicy"
}

# Task 5.3 — CloudFront distribution using one private ALB VPC origin.
# Default traffic reaches Next.js; /v1/* reaches FastAPI through ALB routing.
# Viewer HTTPS uses the default CloudFront certificate.
# Optional WAF association is provided by the Dev root.
resource "aws_cloudfront_distribution" "this" {
  enabled = true

  # Optional WAFv2 web ACL association (CLOUDFRONT scope). Null leaves the
  # distribution with no association; a non-null ARN comes from the security
  # module via the Dev_Root. This module creates no WAF resource.
  web_acl_id = var.web_acl_id

  # API origin: the internal ALB reached through the edge-created VPC Origin.
  # domain_name is the ALB DNS name (consumed from the backend); the VPC Origin
  # is attached by id. Traffic to the ALB is HTTP on the private path.
  origin {
    origin_id   = "api-vpc-origin"
    domain_name = var.alb_dns_name

    vpc_origin_config {
      vpc_origin_id = aws_cloudfront_vpc_origin.api.id
    }
  }

  # Default behavior — Next.js on ECS Fargate via internal ALB
  default_cache_behavior {
    target_origin_id           = "api-vpc-origin"
    viewer_protocol_policy     = "redirect-to-https"
    cache_policy_id            = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id   = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.security.id

    allowed_methods = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods  = ["GET", "HEAD"]
  }

  # API behavior — Internal ALB / ECS Fargate
  ordered_cache_behavior {
    path_pattern               = "/api/*"
    target_origin_id           = "api-vpc-origin"
    viewer_protocol_policy     = "redirect-to-https"
    cache_policy_id            = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id   = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.security.id

    allowed_methods = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods  = ["GET", "HEAD"]
  }

  # FastAPI v1 routes — Internal ALB / ECS Fargate
  ordered_cache_behavior {
    path_pattern               = "/v1/*"
    target_origin_id           = "api-vpc-origin"
    viewer_protocol_policy     = "redirect-to-https"
    cache_policy_id            = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id   = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.security.id

    allowed_methods = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods  = ["GET", "HEAD"]
  }

  # DEV uses the default CloudFront viewer certificate on the *.cloudfront.net
  # domain; no custom alias and no ACM certificate.
  viewer_certificate {
    cloudfront_default_certificate = true
  }

  # No geo blocking for DEV; the block is required by the provider schema.
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-cloudfront"
  })
}
