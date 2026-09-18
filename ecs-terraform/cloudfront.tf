# ---------------------------------------------------------------------------
# CloudFront — CDN Distribution
#
# Two origins:
#   - S3 (default)  → serves the React frontend  /*
#   - ALB           → serves the Python API       /api/*
#
# Origin Access Control (OAC) is used for the S3 origin so the bucket
# can remain fully private.
#
# HTTP is redirected to HTTPS at the viewer level.
# ---------------------------------------------------------------------------

# OAC — ties CloudFront to the S3 bucket without legacy OAI.
resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "${local.name_prefix}-oac"
  description                       = "OAC for React frontend S3 bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "frontend" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${local.name_prefix}-distribution"
  default_root_object = "index.html"
  price_class         = "PriceClass_100"

  aliases = [
    var.domain_name,
    "www.${var.domain_name}",
  ]

  # ---------------------------------------------------------------------------
  # Origin 1 — S3 (React frontend)
  # ---------------------------------------------------------------------------
  origin {
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id                = "S3-${aws_s3_bucket.frontend.id}"
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  # ---------------------------------------------------------------------------
  # Origin 2 — ALB (Python API)
  # ---------------------------------------------------------------------------
  origin {
    domain_name = aws_lb.ecs_alb.dns_name
    origin_id   = "ALB-${local.name_prefix}"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # ---------------------------------------------------------------------------
  # Default cache behaviour — routes /* to S3
  # ---------------------------------------------------------------------------
  default_cache_behavior {
    target_origin_id       = "S3-${aws_s3_bucket.frontend.id}"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400
  }

  # ---------------------------------------------------------------------------
  # API cache behaviour — routes /api/* to ALB
  # ---------------------------------------------------------------------------
  ordered_cache_behavior {
    path_pattern           = "/api/*"
    target_origin_id       = "ALB-${local.name_prefix}"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    # Do not cache API responses; forward all headers/cookies to the origin.
    forwarded_values {
      query_string = true
      headers      = ["Authorization", "Origin", "Host"]
      cookies {
        forward = "all"
      }
    }

    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 0
  }

  # React SPA — serve index.html for any 403/404 so client-side routing works.
  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 10
  }

  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 10
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.cloudfront.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = {
    Name      = "${local.name_prefix}-cloudfront"
    Component = "cdn"
  }

  depends_on = [aws_acm_certificate_validation.cloudfront]
}
