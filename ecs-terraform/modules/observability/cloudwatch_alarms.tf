# cloudwatch_alarms.tf
#
# This file is the observability module's primary resource file. Following the
# project standard (see modules/backend/ecs.tf), the technically-necessary
# terraform {} version-constraint block and the locals { name_prefix } block live
# here rather than in organizational-only versions.tf / locals.tf files.
#
# The six CloudWatch metric alarms (ECS CPU, ECS memory, ALB unhealthy host, ALB
# target 5xx, ALB ELB 5xx, ALB target response-time latency) are added to this
# file in tasks 3 and 4. All alarms are notification/visibility only and are
# distinct from the backend module's autoscaling CPU target-tracking policy; this
# module declares no aws_cloudwatch_log_group (the backend owns the ECS app log
# group) and no autoscaling policy.

# A version-constraint block is technically necessary, so it is permitted here
# rather than creating a separate versions.tf (project standard: no
# organizational-only files). Pins match the dev root and sibling modules so the
# root and its modules resolve a single compatible provider set. This module
# declares no backend block and no provider block; it inherits the default AWS
# provider configured in envs/dev/providers.tf.
terraform {
  required_version = "~> 1.16.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.67.0"
    }
  }
}

# name_prefix lives here rather than in a separate locals.tf (project standard).
# It is the single naming base for every observability resource.
locals {
  name_prefix = "${var.app_name}-${var.environment}"
}

# ---------------------------------------------------------------------------
# ECS service CPU and memory notification alarms (R4)
#
# These are NOTIFICATION/visibility alarms on the ECS service's AWS/ECS metrics,
# dimensioned by ClusterName and ServiceName sourced from backend outputs (never
# hardcoded). They are deliberately DISTINCT from the backend module's autoscaling
# CPU target-tracking policy (aws_appautoscaling_policy.cpu): this module creates
# no autoscaling policy and no scalable target, and does not alter scaling
# behavior. Each alarm uses the Average statistic, a GreaterThanOrEqualToThreshold
# comparison, and configurable threshold/period/evaluation-period variables with
# cost-conscious DEV defaults.
#
# treat_missing_data = "notBreaching": in DEV the service can run with
# desired_count = 0 (first-deployment bootstrap) or very low traffic, so ECS may
# publish no datapoints. Treating missing data as not breaching prevents spurious
# ALARM states when no tasks are running.
#
# alarm_actions / ok_actions are intentionally empty here. The optional SNS
# notification path and the local.alarm_actions wiring are added in task 6; until
# then every alarm has an empty action list, matching the SNS-disabled-by-default
# design (R9.2).

resource "aws_cloudwatch_metric_alarm" "ecs_cpu" {
  alarm_name        = "${local.name_prefix}-ecs-cpu-high"
  alarm_description = "ECS service average CPU utilization >= ${var.cpu_alarm_threshold}% for ${var.ecs_alarm_evaluation_periods} period(s). Compute saturation can slow or interrupt a student's live assessment."

  namespace   = "AWS/ECS"
  metric_name = "CPUUtilization"
  statistic   = "Average"

  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = var.ecs_service_name
  }

  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = var.cpu_alarm_threshold
  period              = var.ecs_alarm_period
  evaluation_periods  = var.ecs_alarm_evaluation_periods
  treat_missing_data  = "notBreaching"

  # Notify on alarm and on recovery via the optional SNS topic; empty when
  # enable_sns is false (SNS disabled by default), so no action is taken.
  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions

  tags = merge(var.tags, { Name = "${local.name_prefix}-ecs-cpu-high" })
}

resource "aws_cloudwatch_metric_alarm" "ecs_memory" {
  alarm_name        = "${local.name_prefix}-ecs-memory-high"
  alarm_description = "ECS service average memory utilization >= ${var.memory_alarm_threshold}% for ${var.ecs_alarm_evaluation_periods} period(s). Memory exhaustion can OOM a task and drop a student's submission."

  namespace   = "AWS/ECS"
  metric_name = "MemoryUtilization"
  statistic   = "Average"

  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = var.ecs_service_name
  }

  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = var.memory_alarm_threshold
  period              = var.ecs_alarm_period
  evaluation_periods  = var.ecs_alarm_evaluation_periods
  treat_missing_data  = "notBreaching"

  # Notify on alarm and on recovery via the optional SNS topic; empty when
  # enable_sns is false (SNS disabled by default), so no action is taken.
  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions

  tags = merge(var.tags, { Name = "${local.name_prefix}-ecs-memory-high" })
}

# ---------------------------------------------------------------------------
# ALB alarms (R5, R6, R7, R14)
#
# Notification/visibility alarms on the internal ALB's AWS/ApplicationELB metrics.
# Dimensions use the ARN SUFFIX form required by CloudWatch:
#   LoadBalancer = app/<name>/<id>        (from var.alb_arn_suffix)
#   TargetGroup  = targetgroup/<name>/<id> (from var.target_group_arn_suffix)
# Both come from backend outputs — never hardcoded.
#
# treat_missing_data = "notBreaching": DEV runs at low/zero traffic (and
# desired_count may be 0 during bootstrap), so these metrics often report no
# datapoints. Not-breaching avoids spurious ALARM states when there is no traffic.
#
# alarm_actions / ok_actions stay empty until the SNS path is wired in task 6
# (SNS disabled by default).

# Unhealthy targets behind the ALB (R5). Statistic Maximum over the period so a
# single unhealthy host in any datapoint is caught. Dimensioned by TargetGroup +
# LoadBalancer. Signals lost API capacity: students may be unable to reach the
# service mid-assessment.
resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_hosts" {
  alarm_name        = "${local.name_prefix}-alb-unhealthy-hosts"
  alarm_description = "ALB reports >= ${var.unhealthy_host_threshold} unhealthy target(s) for ${var.unhealthy_host_evaluation_periods} period(s). Lost API capacity can stop students reaching the assessment service."

  namespace   = "AWS/ApplicationELB"
  metric_name = "UnHealthyHostCount"
  statistic   = "Maximum"

  dimensions = {
    TargetGroup  = var.target_group_arn_suffix
    LoadBalancer = var.alb_arn_suffix
  }

  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = var.unhealthy_host_threshold
  period              = var.unhealthy_host_period
  evaluation_periods  = var.unhealthy_host_evaluation_periods
  treat_missing_data  = "notBreaching"

  # Notify on alarm and on recovery via the optional SNS topic; empty when
  # enable_sns is false (SNS disabled by default), so no action is taken.
  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions

  tags = merge(var.tags, { Name = "${local.name_prefix}-alb-unhealthy-hosts" })
}

# Target-generated HTTP 5xx responses (R6). Statistic Sum over the period.
# Dimensioned by TargetGroup + LoadBalancer so this reflects errors originating in
# the application, distinct from load-balancer-level 5xx below. Application server
# errors break assessment submissions.
resource "aws_cloudwatch_metric_alarm" "alb_target_5xx" {
  alarm_name        = "${local.name_prefix}-alb-target-5xx"
  alarm_description = "ALB target 5xx (HTTPCode_Target_5XX_Count) sum >= ${var.target_5xx_threshold} for ${var.target_5xx_evaluation_periods} period(s). Application server errors break assessment submissions."

  namespace   = "AWS/ApplicationELB"
  metric_name = "HTTPCode_Target_5XX_Count"
  statistic   = "Sum"

  dimensions = {
    TargetGroup  = var.target_group_arn_suffix
    LoadBalancer = var.alb_arn_suffix
  }

  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = var.target_5xx_threshold
  period              = var.target_5xx_period
  evaluation_periods  = var.target_5xx_evaluation_periods
  treat_missing_data  = "notBreaching"

  # Notify on alarm and on recovery via the optional SNS topic; empty when
  # enable_sns is false (SNS disabled by default), so no action is taken.
  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions

  tags = merge(var.tags, { Name = "${local.name_prefix}-alb-target-5xx" })
}

# Load-balancer-generated HTTP 5xx responses (R7). Statistic Sum over the period.
# Dimensioned by LoadBalancer ONLY (no TargetGroup) so it captures failures at the
# ALB itself, distinct from the target 5xx alarm above. Separate resource.
resource "aws_cloudwatch_metric_alarm" "alb_elb_5xx" {
  alarm_name        = "${local.name_prefix}-alb-elb-5xx"
  alarm_description = "ALB load-balancer 5xx (HTTPCode_ELB_5XX_Count) sum >= ${var.elb_5xx_threshold} for ${var.elb_5xx_evaluation_periods} period(s). Load-balancer-level failures mid-session, distinct from application errors."

  namespace   = "AWS/ApplicationELB"
  metric_name = "HTTPCode_ELB_5XX_Count"
  statistic   = "Sum"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }

  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = var.elb_5xx_threshold
  period              = var.elb_5xx_period
  evaluation_periods  = var.elb_5xx_evaluation_periods
  treat_missing_data  = "notBreaching"

  # Notify on alarm and on recovery via the optional SNS topic; empty when
  # enable_sns is false (SNS disabled by default), so no action is taken.
  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions

  tags = merge(var.tags, { Name = "${local.name_prefix}-alb-elb-5xx" })
}

# Target response-time / latency (R14). Uses an extended percentile statistic
# (default p95) rather than Average so the alarm reflects tail latency.
# TargetResponseTime is in seconds. Dimensioned by TargetGroup + LoadBalancer.
# High tail latency slows or interrupts a student's live assessment and precedes
# timeouts and failed submissions.
resource "aws_cloudwatch_metric_alarm" "alb_target_latency" {
  alarm_name        = "${local.name_prefix}-alb-target-latency"
  alarm_description = "ALB TargetResponseTime ${var.latency_alarm_statistic} >= ${var.latency_threshold_seconds}s for ${var.latency_alarm_evaluation_periods} period(s). High tail latency degrades or interrupts a student's live assessment."

  namespace          = "AWS/ApplicationELB"
  metric_name        = "TargetResponseTime"
  extended_statistic = var.latency_alarm_statistic

  dimensions = {
    TargetGroup  = var.target_group_arn_suffix
    LoadBalancer = var.alb_arn_suffix
  }

  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = var.latency_threshold_seconds
  period              = var.latency_alarm_period
  evaluation_periods  = var.latency_alarm_evaluation_periods
  treat_missing_data  = "notBreaching"

  # Notify on alarm and on recovery via the optional SNS topic; empty when
  # enable_sns is false (SNS disabled by default), so no action is taken.
  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions

  tags = merge(var.tags, { Name = "${local.name_prefix}-alb-target-latency" })
}
