locals {
  # Single naming base for every observability resource.
  name_prefix = "${var.app_name}-${var.environment}"


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

  # Alarm action list consumed by every alarm in cloudwatch_alarms.tf. Empty when
  # SNS is disabled (so alarms have no actions); the single topic ARN when enabled.
  alarm_actions = var.enable_sns ? [aws_sns_topic.alarms[0].arn] : []
}
