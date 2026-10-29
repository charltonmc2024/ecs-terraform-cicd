# dashboard.tf
#
# A single CloudWatch dashboard (R8) presenting the application and infrastructure
# metrics operators need to assess platform health at a glance. The body is built
# with jsonencode from locals so every metric dimension value comes from module
# inputs/references — no hardcoded dimension strings.
#
# Standard CloudWatch metrics only (AWS/ECS, AWS/ApplicationELB, and optionally
# AWS/CloudFront). This module creates no log group and no alarm here; the six
# alarms live in cloudwatch_alarms.tf and the ECS app log group is backend-owned.
#
# Widget metric region: ECS and ALB metrics are published in the deploy region,
# resolved via the aws_region data source (never a hardcoded region). CloudFront
# publishes AWS/CloudFront metrics only in us-east-1, so the optional CloudFront
# widgets pin region = "us-east-1" — an architectural requirement of CloudFront,
# not an account-specific identifier.

data "aws_region" "current" {}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${local.name_prefix}-observability"

  dashboard_body = jsonencode({
    widgets = local.dashboard_widgets
  })
}
