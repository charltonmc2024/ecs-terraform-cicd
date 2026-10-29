locals {
  # Single naming base for every security resource name and Name tag; the prefix
  # is derived once here and never recomputed inline elsewhere in the module.
  name_prefix = "${var.app_name}-${var.environment}"


  # One new trail is created only when CloudTrail is enabled AND no suitable
  # existing trail is being reused.
  create_trail = var.enable_cloudtrail && !var.reuse_existing_trail

  # Derived names/ARNs (no hardcoded account id, region, or ARN). The trail ARN
  # is constructed from account + region + name so the bucket policy can scope
  # aws:SourceArn without creating a bucket<->trail dependency cycle.
  trail_name        = "${local.name_prefix}-trail"
  trail_bucket_name = "${local.name_prefix}-cloudtrail-logs"
  trail_arn         = "arn:aws:cloudtrail:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:trail/${local.trail_name}"

  # Topic ARN consumed by the EventBridge targets in eventbridge.tf (Task 7).
  # Empty list when security alerts are disabled, so a count-gated target can
  # reference it safely.
  security_alerts_topic_arn = one(aws_sns_topic.security_alerts[*].arn)


  # Whether each managed group / the rate rule blocks, derived from the *_mode
  # inputs. true => Block_Mode, false => Count_Mode (the default).
  waf_common_block    = var.waf_common_rule_set_mode == "Block_Mode"
  waf_rate_block      = var.waf_rate_based_rule_mode == "Block_Mode"
  waf_known_bad_block = var.waf_known_bad_inputs_mode == "Block_Mode"
}
