# sns.tf
#
# Optional SNS notification path for the CloudWatch alarms (R9), DISABLED by
# default (var.enable_sns = false). When disabled, every resource here is
# count-gated to zero, so the DEV plan contains NO SNS resources and
# local.alarm_actions is an empty list — the six alarms therefore have empty
# alarm_actions/ok_actions (R9.2).
#
# Encryption-at-rest decision (R9 / operator-approved): the topic is created
# WITHOUT server-side encryption (no kms_master_key_id). This is intentional and
# required for correctness: a CloudWatch alarm CANNOT publish to an SNS topic
# encrypted with the AWS-managed key alias/aws/sns (the managed key policy cannot
# be modified to grant CloudWatch kms:Decrypt/kms:GenerateDataKey), so the alarm
# action would fail silently. Reliable encrypted delivery would require a
# customer-managed KMS key with an explicit key policy, which adds recurring cost
# and is intentionally NOT introduced for DEV. SNS still protects data in transit
# with TLS, and alarm payloads carry only alarm-state text (no PII, answers, or
# secrets). A CMK path can be added later if encryption at rest is required.
#
# Ref: AWS re:Post "Configure a CloudWatch alarm with an encrypted SNS topic".

# Account id used to scope the topic policy's SourceAccount condition (no
# hardcoded account id).
data "aws_caller_identity" "current" {}

# Single alarm notification topic, created only when SNS is enabled.
resource "aws_sns_topic" "alarms" {
  count = var.enable_sns ? 1 : 0

  name = "${local.name_prefix}-alarms"

  tags = merge(var.tags, { Name = "${local.name_prefix}-alarms" })
}

# Topic policy allowing the CloudWatch Alarms service to publish to the topic.
# Without this, CloudWatch alarm actions fail with "not authorized to perform
# SNS:Publish". Scoped to this account via aws:SourceAccount.
data "aws_iam_policy_document" "alarms_topic" {
  count = var.enable_sns ? 1 : 0

  statement {
    sid    = "AllowCloudWatchAlarmsPublish"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }

    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.alarms[0].arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_sns_topic_policy" "alarms" {
  count = var.enable_sns ? 1 : 0

  arn    = aws_sns_topic.alarms[0].arn
  policy = data.aws_iam_policy_document.alarms_topic[0].json
}

# Optional email subscription. Created only when SNS is enabled AND an email
# endpoint is supplied; when enabled with an empty email the topic exists with no
# subscription (R9.4, R9.5). The endpoint is operational config supplied via
# variable, never hardcoded and never a secret.
resource "aws_sns_topic_subscription" "alarms_email" {
  count = var.enable_sns && trimspace(var.sns_notification_email) != "" ? 1 : 0

  topic_arn = aws_sns_topic.alarms[0].arn
  protocol  = "email"
  endpoint  = var.sns_notification_email
}

# Alarm action list consumed by every alarm in cloudwatch_alarms.tf. Empty when
# SNS is disabled (so alarms have no actions); the single topic ARN when enabled.
locals {
  alarm_actions = var.enable_sns ? [aws_sns_topic.alarms[0].arn] : []
}
