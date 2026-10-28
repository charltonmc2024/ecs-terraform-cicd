# eventbridge.tf
#
# Optional Amazon EventBridge security-event rules (R9), count-gated by
# var.enable_security_alerts (default false). When disabled the module creates
# ZERO EventBridge resources. When enabled, three narrowly scoped rules on the
# DEFAULT event bus match security-relevant AWS API activity and publish the
# matching event to the SNS security-alerts topic from sns.tf (Task 6).
#
# ACTIVE-TRAIL DEPENDENCY (important): these rules match events of
# detail-type "AWS API Call via CloudTrail", which EventBridge only receives
# when a suitable ACTIVE CloudTrail trail delivers management events to the
# default bus — either a reused existing trail with IsLogging = true OR the
# module's optional new trail (enable_cloudtrail = true, see cloudtrail.tf).
# Without such an active trail these rules never match. This module does NOT
# auto-enable CloudTrail, and reuse_existing_trail = true does NOT by itself
# guarantee logging — the operator must confirm IsLogging = true (documented in
# cloudtrail.tf).
#
# Cost / scope: default event bus only; AWS management events (no custom
# events); no Lambda, no custom event bus, no schedule/scheduler, no archive,
# no replay, no pipe, and no extra logging service. Patterns are narrow
# (specific eventSource + eventName) to avoid excessive notifications.
#
# SNS permission: the targets publish to local.security_alerts_topic_arn. The
# topic policy in sns.tf grants events.amazonaws.com SNS:Publish scoped by
# aws:SourceAccount and an ArnLike aws:SourceArn on this account/region's
# arn:aws:events:...:rule/* — which already covers the rules below, so no
# circular dependency (restricting the policy to these specific rule ARNs would
# create a cycle: policy -> rule ARNs -> rules -> target the topic).

# Rule 1 — IAM policy / permission changes.
resource "aws_cloudwatch_event_rule" "iam_changes" {
  count = var.enable_security_alerts ? 1 : 0

  name        = "${local.name_prefix}-iam-changes"
  description = "Security alert: IAM policy and permission changes (via CloudTrail)."

  event_pattern = jsonencode({
    "detail-type" = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource = ["iam.amazonaws.com"]
      eventName = [
        "PutUserPolicy",
        "PutGroupPolicy",
        "PutRolePolicy",
        "AttachUserPolicy",
        "AttachGroupPolicy",
        "AttachRolePolicy",
        "DetachUserPolicy",
        "DetachGroupPolicy",
        "DetachRolePolicy",
        "CreatePolicy",
        "DeletePolicy",
        "CreatePolicyVersion",
        "DeletePolicyVersion",
      ]
    }
  })

  tags = merge(var.tags, { Name = "${local.name_prefix}-iam-changes" })
}

resource "aws_cloudwatch_event_target" "iam_changes" {
  count = var.enable_security_alerts ? 1 : 0

  rule      = aws_cloudwatch_event_rule.iam_changes[0].name
  target_id = "${local.name_prefix}-iam-changes-sns"
  arn       = local.security_alerts_topic_arn

  # The topic policy (sns.tf) must exist before EventBridge can publish.
  depends_on = [aws_sns_topic_policy.security_alerts]
}

# Rule 2 — security group ingress/egress modifications.
resource "aws_cloudwatch_event_rule" "security_group_changes" {
  count = var.enable_security_alerts ? 1 : 0

  name        = "${local.name_prefix}-sg-changes"
  description = "Security alert: security group ingress/egress modifications (via CloudTrail)."

  event_pattern = jsonencode({
    "detail-type" = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource = ["ec2.amazonaws.com"]
      eventName = [
        "AuthorizeSecurityGroupIngress",
        "AuthorizeSecurityGroupEgress",
        "RevokeSecurityGroupIngress",
        "RevokeSecurityGroupEgress",
      ]
    }
  })

  tags = merge(var.tags, { Name = "${local.name_prefix}-sg-changes" })
}

resource "aws_cloudwatch_event_target" "security_group_changes" {
  count = var.enable_security_alerts ? 1 : 0

  rule      = aws_cloudwatch_event_rule.security_group_changes[0].name
  target_id = "${local.name_prefix}-sg-changes-sns"
  arn       = local.security_alerts_topic_arn

  depends_on = [aws_sns_topic_policy.security_alerts]
}

# Rule 3 — CloudTrail configuration changes (tamper detection).
resource "aws_cloudwatch_event_rule" "cloudtrail_changes" {
  count = var.enable_security_alerts ? 1 : 0

  name        = "${local.name_prefix}-cloudtrail-changes"
  description = "Security alert: CloudTrail configuration changes (StopLogging/UpdateTrail/DeleteTrail)."

  event_pattern = jsonencode({
    "detail-type" = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource = ["cloudtrail.amazonaws.com"]
      eventName = [
        "StopLogging",
        "UpdateTrail",
        "DeleteTrail",
      ]
    }
  })

  tags = merge(var.tags, { Name = "${local.name_prefix}-cloudtrail-changes" })
}

resource "aws_cloudwatch_event_target" "cloudtrail_changes" {
  count = var.enable_security_alerts ? 1 : 0

  rule      = aws_cloudwatch_event_rule.cloudtrail_changes[0].name
  target_id = "${local.name_prefix}-cloudtrail-changes-sns"
  arn       = local.security_alerts_topic_arn

  depends_on = [aws_sns_topic_policy.security_alerts]
}
