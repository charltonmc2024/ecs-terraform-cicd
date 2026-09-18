# ---------------------------------------------------------------------------
# Route 53 — Hosted Zone + DNS Records
#
# The hosted zone for the domain is created here if it does not already
# exist. After apply, update your domain registrar with the NS records
# output by aws_route53_zone.main.name_servers.
#
# All alias records point to CloudFront — both apex and www, IPv4 and IPv6.
# ---------------------------------------------------------------------------

resource "aws_route53_zone" "main" {
  name = var.domain_name

  tags = {
    Name = "${var.app_name}-${var.environment}-hosted-zone"
  }
}

# Apex domain → CloudFront (IPv4)
resource "aws_route53_record" "apex" {
  zone_id = aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.frontend.domain_name
    zone_id                = aws_cloudfront_distribution.frontend.hosted_zone_id
    evaluate_target_health = false
  }
}

# Apex domain → CloudFront (IPv6)
resource "aws_route53_record" "apex_ipv6" {
  zone_id = aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.frontend.domain_name
    zone_id                = aws_cloudfront_distribution.frontend.hosted_zone_id
    evaluate_target_health = false
  }
}

# www subdomain → CloudFront (IPv4)
resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "www.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.frontend.domain_name
    zone_id                = aws_cloudfront_distribution.frontend.hosted_zone_id
    evaluate_target_health = false
  }
}

# www subdomain → CloudFront (IPv6)
resource "aws_route53_record" "www_ipv6" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "www.${var.domain_name}"
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.frontend.domain_name
    zone_id                = aws_cloudfront_distribution.frontend.hosted_zone_id
    evaluate_target_health = false
  }
}

# ---------------------------------------------------------------------------
# Output the nameservers so you can update your domain registrar.
# ---------------------------------------------------------------------------
