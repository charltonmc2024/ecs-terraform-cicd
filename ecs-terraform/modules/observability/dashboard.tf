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

locals {
  # Region for ECS/ALB widgets, resolved from the inherited provider.
  dashboard_region = data.aws_region.current.region

  # ECS and ALB widgets (always present). Each metric row carries its dimension
  # name/value pairs sourced from module variables.
  ecs_alb_widgets = [
    {
      type   = "metric"
      x      = 0
      y      = 0
      width  = 12
      height = 6
      properties = {
        title  = "ECS CPU Utilization (%)"
        view   = "timeSeries"
        region = local.dashboard_region
        stat   = "Average"
        metrics = [
          ["AWS/ECS", "CPUUtilization", "ClusterName", var.ecs_cluster_name, "ServiceName", var.ecs_service_name]
        ]
      }
    },
    {
      type   = "metric"
      x      = 12
      y      = 0
      width  = 12
      height = 6
      properties = {
        title  = "ECS Memory Utilization (%)"
        view   = "timeSeries"
        region = local.dashboard_region
        stat   = "Average"
        metrics = [
          ["AWS/ECS", "MemoryUtilization", "ClusterName", var.ecs_cluster_name, "ServiceName", var.ecs_service_name]
        ]
      }
    },
    {
      type   = "metric"
      x      = 0
      y      = 6
      width  = 12
      height = 6
      properties = {
        title  = "ALB Request Count"
        view   = "timeSeries"
        region = local.dashboard_region
        stat   = "Sum"
        metrics = [
          ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_arn_suffix]
        ]
      }
    },
    {
      type   = "metric"
      x      = 12
      y      = 6
      width  = 12
      height = 6
      properties = {
        title  = "ALB 5xx Errors (target vs load balancer)"
        view   = "timeSeries"
        region = local.dashboard_region
        stat   = "Sum"
        metrics = [
          ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "TargetGroup", var.target_group_arn_suffix, "LoadBalancer", var.alb_arn_suffix],
          ["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", "LoadBalancer", var.alb_arn_suffix]
        ]
      }
    },
    {
      type   = "metric"
      x      = 0
      y      = 12
      width  = 12
      height = 6
      properties = {
        title  = "ALB Target Host Health (healthy vs unhealthy)"
        view   = "timeSeries"
        region = local.dashboard_region
        stat   = "Maximum"
        metrics = [
          ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", var.target_group_arn_suffix, "LoadBalancer", var.alb_arn_suffix],
          ["AWS/ApplicationELB", "UnHealthyHostCount", "TargetGroup", var.target_group_arn_suffix, "LoadBalancer", var.alb_arn_suffix]
        ]
      }
    },
    {
      type   = "metric"
      x      = 12
      y      = 12
      width  = 12
      height = 6
      properties = {
        title  = "ALB Target Response Time ${var.latency_alarm_statistic} (seconds)"
        view   = "timeSeries"
        region = local.dashboard_region
        stat   = var.latency_alarm_statistic
        metrics = [
          ["AWS/ApplicationELB", "TargetResponseTime", "TargetGroup", var.target_group_arn_suffix, "LoadBalancer", var.alb_arn_suffix]
        ]
      }
    }
  ]

  # Optional CloudFront widgets (R8.4/R8.5). CloudFront metrics exist only in
  # us-east-1. Present only when enable_cloudfront_widgets is true AND a
  # distribution id is supplied. CloudFront dimensions require Region = "Global".
  cloudfront_widgets = var.enable_cloudfront_widgets && var.cloudfront_distribution_id != null ? [
    {
      type   = "metric"
      x      = 0
      y      = 18
      width  = 12
      height = 6
      properties = {
        title  = "CloudFront Requests"
        view   = "timeSeries"
        region = "us-east-1"
        stat   = "Sum"
        metrics = [
          ["AWS/CloudFront", "Requests", "DistributionId", var.cloudfront_distribution_id, "Region", "Global"]
        ]
      }
    },
    {
      type   = "metric"
      x      = 12
      y      = 18
      width  = 12
      height = 6
      properties = {
        title  = "CloudFront Total Error Rate (%)"
        view   = "timeSeries"
        region = "us-east-1"
        stat   = "Average"
        metrics = [
          ["AWS/CloudFront", "TotalErrorRate", "DistributionId", var.cloudfront_distribution_id, "Region", "Global"]
        ]
      }
    }
  ] : []

  dashboard_widgets = concat(local.ecs_alb_widgets, local.cloudfront_widgets)
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${local.name_prefix}-observability"

  dashboard_body = jsonencode({
    widgets = local.dashboard_widgets
  })
}
