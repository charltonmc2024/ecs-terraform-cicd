# waf.tf
#
# Optional AWS WAFv2 web ACL (R3, R4, R5), count-gated by var.enable_waf
# (default false). When disabled the module creates ZERO WAF resources and the
# CloudFront distribution has no web ACL association (the edge web_acl_id
# receives null in Task 9). CloudFront is the platform's only internet-facing
# resource, so this web ACL is the primary application-layer request filter.
#
# scope = "CLOUDFRONT" REQUIRES the resource to live in us-east-1. This module
# names no region; the Dev_Root maps the aws.us_east_1 provider alias into the
# module (providers = { aws = aws.us_east_1 }), so every resource here resolves
# to us-east-1.
#
# Cost-optimized baseline (both start in COUNT): the AWS Managed Common Rule Set
# plus exactly one rate-based rule. The optional AWS Managed Known Bad Inputs
# group is off by default. Excluded by design: no premium/paid managed group,
# no Bot Control, no CAPTCHA, no Challenge action, and no
# aws_wafv2_web_acl_logging_configuration (request-level WAF logging is a
# deferred production-hardening concern).
#
# COUNT vs BLOCK semantics (the important part):
#   - Managed rule groups use override_action. Count_Mode => override_action
#     { count {} }, which overrides EVERY rule in the group to COUNT (inspect +
#     label, never block). Block_Mode => override_action { none {} }, which
#     applies NO override so each rule in the group uses its OWN normal action
#     (typically block). Using "none" rather than a top-level "block" is what
#     lets the group transition to its intended behavior WITHOUT force-blocking
#     every rule.
#   - The rate-based rule is a non-managed rule, so it carries a direct action:
#     Count_Mode => action { count {} }, Block_Mode => action { block {} }.
# As delivered (defaults) every rule is in COUNT, so matched requests are
# counted and labeled but never blocked; the only non-count disposition is the
# web ACL default_action, which defaults to "allow".

resource "aws_wafv2_web_acl" "this" {
  count = var.enable_waf ? 1 : 0

  name  = "${local.name_prefix}-waf"
  scope = "CLOUDFRONT"

  # Requests matching no rule take this action; defaults to allow so only rule
  # matches are evaluated (R3.4).
  dynamic "default_action" {
    for_each = var.waf_default_action == "block" ? [1] : []
    content {
      block {}
    }
  }
  dynamic "default_action" {
    for_each = var.waf_default_action == "allow" ? [1] : []
    content {
      allow {}
    }
  }

  # Rule 1 — AWS Managed Common Rule Set (priority 1). override_action count{}
  # (default) counts every rule in the group; none{} lets the group's own rule
  # actions apply for the Block_Mode transition (R3.6, R4.1, R4.3, R4.4).
  rule {
    name     = "${local.name_prefix}-common-rule-set"
    priority = 1

    override_action {
      dynamic "count" {
        for_each = local.waf_common_block ? [] : [1]
        content {}
      }
      dynamic "none" {
        for_each = local.waf_common_block ? [1] : []
        content {}
      }
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      sampled_requests_enabled   = true
      metric_name                = "${local.name_prefix}-common-rule-set"
    }
  }

  # Rule 2 — rate-based rule (priority 2). A non-managed rule carries a direct
  # action: count{} (default) or block{} when waf_rate_based_rule_mode is
  # Block_Mode. Aggregates per source IP over WAFv2's fixed 300-second window
  # (R3.7, R3.11, R4.5).
  rule {
    name     = "${local.name_prefix}-rate-limit"
    priority = 2

    action {
      dynamic "count" {
        for_each = local.waf_rate_block ? [] : [1]
        content {}
      }
      dynamic "block" {
        for_each = local.waf_rate_block ? [1] : []
        content {}
      }
    }

    statement {
      rate_based_statement {
        limit              = var.waf_rate_limit
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      sampled_requests_enabled   = true
      metric_name                = "${local.name_prefix}-rate-limit"
    }
  }

  # Rule 3 — OPTIONAL AWS Managed Known Bad Inputs (priority 3), present only
  # when enable_known_bad_inputs is true, so the baseline stays Common + rate
  # rule. Same override_action semantics as Rule 1 (R3.8).
  dynamic "rule" {
    for_each = var.enable_known_bad_inputs ? [1] : []
    content {
      name     = "${local.name_prefix}-known-bad-inputs"
      priority = 3

      override_action {
        dynamic "count" {
          for_each = local.waf_known_bad_block ? [] : [1]
          content {}
        }
        dynamic "none" {
          for_each = local.waf_known_bad_block ? [1] : []
          content {}
        }
      }

      statement {
        managed_rule_group_statement {
          name        = "AWSManagedRulesKnownBadInputsRuleSet"
          vendor_name = "AWS"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        sampled_requests_enabled   = true
        metric_name                = "${local.name_prefix}-known-bad-inputs"
      }
    }
  }

  # Web ACL-level visibility (R5.1).
  visibility_config {
    cloudwatch_metrics_enabled = true
    sampled_requests_enabled   = true
    metric_name                = "${local.name_prefix}-waf"
  }

  tags = merge(var.tags, { Name = "${local.name_prefix}-waf" })
}
