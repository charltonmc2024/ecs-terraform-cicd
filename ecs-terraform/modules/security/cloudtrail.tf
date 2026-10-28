# cloudtrail.tf
#
# Optional, reuse-first management-events CloudTrail trail (R8). Every resource
# here is gated by `var.enable_cloudtrail && !var.reuse_existing_trail`, so:
#   - Default DEV (enable_cloudtrail = false): ZERO trail resources are created.
#   - reuse_existing_trail = true: ZERO trail resources are created even if
#     enable_cloudtrail is true (a suitable existing trail is reused instead).
#   - enable_cloudtrail = true AND reuse_existing_trail = false: exactly one new
#     management-events-only trail and its backing S3 bucket are created.
#
# CloudTrail Event History is unaffected: AWS always provides the last 90 days
# of management events with no configured trail. This module never disables or
# replaces Event History; an optional trail only adds durable S3 delivery with
# longer, bounded retention.
#
# REUSE-FIRST (operator step, documented — not a Terraform data source).
# Terraform cannot reliably enumerate "any suitable existing trail," so the
# reuse decision is made by the operator BEFORE apply and recorded in
# var.reuse_existing_trail. A trail counts as reusable ONLY when BOTH hold:
#   1. Configuration coverage — a multi-region trail that includes management
#      events for this account/region, verified with:
#        aws cloudtrail describe-trails
#      (inspect IsMultiRegionTrail and the management-event / event-selector
#      configuration).
#   2. Active logging — the trail is actively logging, verified with:
#        aws cloudtrail get-trail-status
#      where the returned IsLogging flag is true.
# A configured-but-stopped trail (IsLogging = false) is NOT reusable: it does
# not deliver API-call events and does not satisfy the EventBridge dependency in
# eventbridge.tf. A trail name existing is NOT sufficient. If a future
# requirement needs Terraform to target a specific existing trail by name/ARN,
# add a dedicated input variable then rather than guessing one now.
#
# Excluded by design (cost / scope): NO data events, NO CloudTrail Insights, NO
# CloudTrail Lake, NO CloudWatch Logs delivery, and NO customer-managed KMS key
# (SSE-S3 AWS-managed encryption is sufficient for DEV).

locals {
  # One new trail is created only when CloudTrail is enabled AND no suitable
  # existing trail is being reused.
  create_trail = var.enable_cloudtrail && !var.reuse_existing_trail

  # Derived names/ARNs (no hardcoded account id, region, or ARN). The trail ARN
  # is constructed from account + region + name so the bucket policy can scope
  # aws:SourceArn without creating a bucket<->trail dependency cycle.
  trail_name        = "${local.name_prefix}-trail"
  trail_bucket_name = "${local.name_prefix}-cloudtrail-logs"
  trail_arn         = "arn:aws:cloudtrail:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:trail/${local.trail_name}"
}

# Region for the constructed trail ARN (no hardcoded region).
data "aws_region" "current" {}

# ---------------------------------------------------------------------------
# S3 logging bucket (created only with a new trail)
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "trail" {
  count = local.create_trail ? 1 : 0

  bucket = local.trail_bucket_name

  tags = merge(var.tags, { Name = local.trail_bucket_name })
}

# Block all public access on the trail bucket (all four settings).
resource "aws_s3_bucket_public_access_block" "trail" {
  count = local.create_trail ? 1 : 0

  bucket = aws_s3_bucket.trail[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# SSE-S3 (AWS-managed AES256) encryption at rest — no customer-managed KMS key.
resource "aws_s3_bucket_server_side_encryption_configuration" "trail" {
  count = local.create_trail ? 1 : 0

  bucket = aws_s3_bucket.trail[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Lifecycle expiry so trail objects are never retained indefinitely; bounded by
# var.cloudtrail_retention_days (<= 365).
resource "aws_s3_bucket_lifecycle_configuration" "trail" {
  count = local.create_trail ? 1 : 0

  bucket = aws_s3_bucket.trail[0].id

  rule {
    id     = "expire-trail-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = var.cloudtrail_retention_days
    }
  }
}

# REQUIRED least-privilege bucket policy for CloudTrail log delivery. Without
# it CloudTrail cannot write log files to the bucket. Grants exactly:
#   - s3:GetBucketAcl on the bucket, and
#   - s3:PutObject under AWSLogs/<account-id>/* with the bucket-owner-full-control ACL,
# to the cloudtrail.amazonaws.com service principal, additionally scoped by
# aws:SourceArn (this trail) and aws:SourceAccount (this account). No account
# id, bucket ARN, or trail ARN is hardcoded.
data "aws_iam_policy_document" "trail" {
  count = local.create_trail ? 1 : 0

  statement {
    sid    = "AWSCloudTrailAclCheck"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.trail[0].arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  statement {
    sid    = "AWSCloudTrailWrite"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.trail[0].arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_s3_bucket_policy" "trail" {
  count = local.create_trail ? 1 : 0

  bucket = aws_s3_bucket.trail[0].id
  policy = data.aws_iam_policy_document.trail[0].json
}

# ---------------------------------------------------------------------------
# The management-events-only trail
# ---------------------------------------------------------------------------

resource "aws_cloudtrail" "this" {
  count = local.create_trail ? 1 : 0

  name           = local.trail_name
  s3_bucket_name = aws_s3_bucket.trail[0].id

  # Management events only, read + write; no data-event selectors.
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true

  event_selector {
    read_write_type           = "All"
    include_management_events = true
  }

  tags = merge(var.tags, { Name = local.trail_name })

  # Ensure the bucket policy exists before the trail validates write access.
  depends_on = [aws_s3_bucket_policy.trail]
}
