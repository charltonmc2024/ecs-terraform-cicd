# outputs.tf
#
# Minimal output surface (R12.5, R12.6): only the two values the dev root
# re-exports for operators. No output carries or derives from a secret value
# (R13.4).

# Name of the CloudWatch dashboard created in dashboard.tf. Operators use this to
# open the dashboard; CI/CD may reference it.
output "dashboard_name" {
  description = "Name of the CloudWatch observability dashboard."
  value       = aws_cloudwatch_dashboard.main.dashboard_name
}

# ARN of the optional alarm SNS topic. The topic is count-gated by var.enable_sns,
# so aws_sns_topic.alarms is a (0- or 1-element) list. one(...) returns the single
# ARN when SNS is enabled and null when it is disabled (count = 0) — no index-out-
# of-range error and a clean null for downstream consumers (R9, R12.6).
output "sns_topic_arn" {
  description = "ARN of the alarm notification SNS topic, or null when enable_sns is false."
  value       = one(aws_sns_topic.alarms[*].arn)
}
