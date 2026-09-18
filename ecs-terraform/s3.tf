# ---------------------------------------------------------------------------
# S3 — React Frontend Bucket
#
# The bucket is kept private. CloudFront accesses it through an Origin
# Access Control (OAC) rather than a public bucket policy.
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "frontend" {
  bucket        = "${local.name_prefix}-frontend"
  force_destroy = true

  tags = {
    Name      = "${local.name_prefix}-frontend"
    Component = "frontend"
  }
}

# Block all public access — CloudFront uses OAC, not public URLs.
resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Encryption at rest using the default AWS-managed S3 key.
resource "aws_s3_bucket_server_side_encryption_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Versioning — useful for rollback of frontend deployments.
resource "aws_s3_bucket_versioning" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Bucket policy — allows CloudFront OAC to read objects.
# The OAC principal is the CloudFront service; the condition pins it to
# the specific distribution so no other distribution can read this bucket.
resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontOAC"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.frontend.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.frontend.arn
          }
        }
      }
    ]
  })
}
