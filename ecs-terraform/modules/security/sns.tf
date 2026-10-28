# sns.tf
#
# Optional SNS security-alerts topic (R10), count-gated by
# var.enable_security_alerts (default false). It is the delivery path for the
# EventBridge security rules added in eventbridge.tf (Task 7): a matched rule
# publishes the event to this topic, which emails a subscribed operator. When
# disabled the module creates ZERO SNS security resources.
#
# This topic is SEPARATE from the observability module's alarm SNS topic and
# does not modify it; this file mirrors that module's conventions (count gating,
# a scoped topic policy, an optional email subscription) for a different
# publisher.
#
# Encryption-at-rest decision (consistent with the observability topic): the
# topic is created WITHOUT server-side encryption (no kms_master_key_id). The
# AWS-managed key alias/aws/sns cannot be used for an AWS service to publish to
# an encrypted topic (its key policy cannot be modified to grant the service
# kms:GenerateDataKey/kms:Decrypt), so encrypted delivery would fail. SNS still
# protects data in transit with TLS, and the payloads carry only AWS API-event
# text (no PII, answers, or secrets). A customer-managed KMS key is intentionally
# NOT introduced for DEV (cost); it is a future production-hardening option. The
# publishing principal here is EventBridge (events.amazonaws.com), not
# CloudWatch.
#
# No Lambda function and no custom notification processor are created.

# Single security-alerts topic.
resource "aws_sns_topic" "security_alerts" {
  count = var.enable_security_alerts ? 1 : 0

  name = "${local.name_prefix}-security-alerts"

  tags = merge(var.tags, { Name = "${local.name_prefix}-security-alerts" })
}

# Topic policy allowing Amazon EventBridge to publish to the topic. Without it,
# EventBridge targets fail to deliver. Least-privilege: exactly one action
# (SNS:Publish) for one service principal (events.amazonaws.com) on this one
# topic, scoped to this account via aws:SourceAccount AND narrowed to EventBridge
# rules in this account/region via an ArnLike aws:SourceArn on
# arn:aws:events:<region>:<account>:rule/*.
#
# Scoping to the specific security rule ARNs from eventbridge.tf (Task 7) would
# create a circular dependency (topic policy -> rule ARNs -> rules -> target the
# topic). The rule/* wildcard avoids that cycle while still restricting the
# publisher to EventBridge rules in this account/region. When Task 7 adds the
# rules, no change to this policy is required — the targets fall within the
# wildcard, so the policy is already complete.
data "aws_iam_policy_document" "security_alerts" {
  count = var.enable_security_alerts ? 1 : 0

  statement {
    sid    = "AllowEventBridgePublish"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.security_alerts[0].arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:events:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:rule/*"]
    }
  }
}

resource "aws_sns_topic_policy" "security_alerts" {
  count = var.enable_security_alerts ? 1 : 0

  arn    = aws_sns_topic.security_alerts[0].arn
  policy = data.aws_iam_policy_document.security_alerts[0].json
}

# Optional email subscription. Created only when security alerts are enabled AND
# a non-empty email endpoint is supplied; enabled with an empty email leaves the
# topic with no subscription. The endpoint is operational config supplied via
# variable, never hardcoded and never a secret.
#
# NOTE: An SNS email subscription is created in a "PendingConfirmation" state.
# AWS sends a confirmation email to the endpoint, and the recipient MUST click
# the confirmation link before any notification is delivered to that address.
resource "aws_sns_topic_subscription" "security_alerts_email" {
  count = var.enable_security_alerts && trimspace(var.security_alerts_email) != "" ? 1 : 0

  topic_arn = aws_sns_topic.security_alerts[0].arn
  protocol  = "email"
  endpoint  = var.security_alerts_email
}

# Topic ARN consumed by the EventBridge targets in eventbridge.tf (Task 7).
# Empty list when security alerts are disabled, so a count-gated target can
# reference it safely.
locals {
  security_alerts_topic_arn = one(aws_sns_topic.security_alerts[*].arn)
}
