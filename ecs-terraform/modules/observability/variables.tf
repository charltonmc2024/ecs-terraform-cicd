# Module input variables for the observability module.
#
# The module is environment-independent: it accepts typed, validated inputs and
# derives all resource names from local.name_prefix. No AWS account IDs, ARNs,
# region strings, or CloudWatch dimension strings are hardcoded here; every such
# value is supplied by the calling root from other modules' outputs. Region is
# NOT a module input — it comes from the AWS provider configured in
# envs/dev/providers.tf, which this module inherits from the calling root.
#
# This module is purely observational: it owns only CloudWatch alarms, a single
# dashboard, and an optional default-off SNS path. It declares NO ECS application
# log group (the backend module owns it) and NO autoscaling policy.

# ---------------------------------------------------------------------------
# Naming
# ---------------------------------------------------------------------------

variable "app_name" {
  description = "Application name used as the first segment of the resource name prefix (e.g. eruditiontx-app)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}[a-z0-9]$", var.app_name))
    error_message = "app_name must be lowercase alphanumeric with hyphens, 3-32 chars, starting with a letter and ending alphanumeric."
  }
}

variable "environment" {
  description = "Environment name used as the second segment of the resource name prefix (e.g. ecs-dev)."
  type        = string

  validation {
    condition     = length(trimspace(var.environment)) > 0
    error_message = "environment must be a non-empty, non-whitespace string."
  }
}

variable "tags" {
  description = "Common tags applied to taggable resources (e.g. Project, Environment, ManagedBy, Owner)."
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# Consumed identifiers / CloudWatch dimensions (from module.backend / module.edge)
#
# These are supplied by the dev root from other modules' outputs — never literals.
# ALB/target-group CloudWatch metrics are dimensioned by the ARN suffix
# (LoadBalancer = app/<name>/<id>, TargetGroup = targetgroup/<name>/<id>).
# ---------------------------------------------------------------------------

variable "ecs_cluster_name" {
  description = "ECS cluster name from module.backend.ecs_cluster_name; used as the ClusterName dimension on ECS alarms and dashboard widgets."
  type        = string

  validation {
    condition     = length(trimspace(var.ecs_cluster_name)) > 0
    error_message = "ecs_cluster_name must be a non-empty string."
  }
}

variable "ecs_service_name" {
  description = "ECS service name from module.backend.ecs_service_name; used as the ServiceName dimension on ECS alarms and dashboard widgets."
  type        = string

  validation {
    condition     = length(trimspace(var.ecs_service_name)) > 0
    error_message = "ecs_service_name must be a non-empty string."
  }
}

variable "alb_arn_suffix" {
  description = "Internal ALB ARN suffix (app/<name>/<id>) from module.backend.alb_arn_suffix; used as the LoadBalancer CloudWatch dimension."
  type        = string

  validation {
    condition     = length(trimspace(var.alb_arn_suffix)) > 0
    error_message = "alb_arn_suffix must be a non-empty string."
  }
}

variable "target_group_arn_suffix" {
  description = "Target group ARN suffix (targetgroup/<name>/<id>) from module.backend.target_group_arn_suffix; used as the TargetGroup CloudWatch dimension."
  type        = string

  validation {
    condition     = length(trimspace(var.target_group_arn_suffix)) > 0
    error_message = "target_group_arn_suffix must be a non-empty string."
  }
}

variable "ecs_log_group_name" {
  description = "Name of the existing backend-owned ECS application CloudWatch log group ($${name_prefix}-app), from module.backend.ecs_log_group_name. Consumed only; this module never creates or recreates the log group."
  type        = string

  validation {
    condition     = var.ecs_log_group_name != null && length(trimspace(var.ecs_log_group_name)) > 0
    error_message = "ecs_log_group_name must be a non-empty, non-null string (the backend-owned ECS application log group is reused, never recreated)."
  }
}

# ---------------------------------------------------------------------------
# CloudFront dashboard widgets (optional). CloudFront publishes AWS/CloudFront
# metrics only in us-east-1, handled in the widget definition when enabled.
# ---------------------------------------------------------------------------

variable "enable_cloudfront_widgets" {
  description = "When true, add CloudFront request-count and error-rate widgets to the dashboard (metrics read from us-east-1). Off by default."
  type        = bool
  default     = false
}

variable "cloudfront_distribution_id" {
  description = "CloudFront distribution id from module.edge, used only when enable_cloudfront_widgets is true. Null when CloudFront widgets are disabled."
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# ECS CPU / memory notification alarms (AWS/ECS, Average). Distinct from the
# backend's autoscaling CPU target-tracking policy.
# ---------------------------------------------------------------------------

variable "cpu_alarm_threshold" {
  description = "ECS service CPU utilization percentage that triggers the CPU alarm (GreaterThanOrEqualToThreshold)."
  type        = number
  default     = 80

  validation {
    condition     = var.cpu_alarm_threshold >= 0 && var.cpu_alarm_threshold <= 100
    error_message = "cpu_alarm_threshold must be a utilization percentage between 0 and 100."
  }
}

variable "memory_alarm_threshold" {
  description = "ECS service memory utilization percentage that triggers the memory alarm (GreaterThanOrEqualToThreshold)."
  type        = number
  default     = 80

  validation {
    condition     = var.memory_alarm_threshold >= 0 && var.memory_alarm_threshold <= 100
    error_message = "memory_alarm_threshold must be a utilization percentage between 0 and 100."
  }
}

variable "ecs_alarm_period" {
  description = "Metric period in seconds for the ECS CPU and memory alarms. Must be a CloudWatch-valid period (10, 30, or a multiple of 60 up to 86400)."
  type        = number
  default     = 60

  validation {
    condition     = contains([10, 30], var.ecs_alarm_period) || (var.ecs_alarm_period % 60 == 0 && var.ecs_alarm_period >= 60 && var.ecs_alarm_period <= 86400)
    error_message = "ecs_alarm_period must be 10, 30, or a multiple of 60 between 60 and 86400 seconds."
  }
}

variable "ecs_alarm_evaluation_periods" {
  description = "Number of consecutive periods the ECS CPU/memory statistic must breach before the alarm fires."
  type        = number
  default     = 3

  validation {
    condition     = var.ecs_alarm_evaluation_periods >= 1 && var.ecs_alarm_evaluation_periods <= 5 && floor(var.ecs_alarm_evaluation_periods) == var.ecs_alarm_evaluation_periods
    error_message = "ecs_alarm_evaluation_periods must be an integer between 1 and 5."
  }
}

# ---------------------------------------------------------------------------
# ALB unhealthy-host alarm (AWS/ApplicationELB UnHealthyHostCount, Maximum).
# ---------------------------------------------------------------------------

variable "unhealthy_host_threshold" {
  description = "Number of unhealthy targets that triggers the unhealthy-host alarm (GreaterThanOrEqualToThreshold)."
  type        = number
  default     = 1

  validation {
    condition     = var.unhealthy_host_threshold >= 1 && var.unhealthy_host_threshold <= 100 && floor(var.unhealthy_host_threshold) == var.unhealthy_host_threshold
    error_message = "unhealthy_host_threshold must be an integer between 1 and 100."
  }
}

variable "unhealthy_host_period" {
  description = "Metric period in seconds for the unhealthy-host alarm. Must be a CloudWatch-valid period (10, 30, or a multiple of 60 up to 86400)."
  type        = number
  default     = 60

  validation {
    condition     = contains([10, 30], var.unhealthy_host_period) || (var.unhealthy_host_period % 60 == 0 && var.unhealthy_host_period >= 60 && var.unhealthy_host_period <= 86400)
    error_message = "unhealthy_host_period must be 10, 30, or a multiple of 60 between 60 and 86400 seconds."
  }
}

variable "unhealthy_host_evaluation_periods" {
  description = "Number of consecutive periods UnHealthyHostCount must breach before the unhealthy-host alarm fires."
  type        = number
  default     = 2

  validation {
    condition     = var.unhealthy_host_evaluation_periods >= 1 && var.unhealthy_host_evaluation_periods <= 100 && floor(var.unhealthy_host_evaluation_periods) == var.unhealthy_host_evaluation_periods
    error_message = "unhealthy_host_evaluation_periods must be an integer between 1 and 100."
  }
}

# ---------------------------------------------------------------------------
# ALB target-group 5xx alarm (AWS/ApplicationELB HTTPCode_Target_5XX_Count, Sum).
# ---------------------------------------------------------------------------

variable "target_5xx_threshold" {
  description = "Count of target-generated HTTP 5xx responses in a period that triggers the target 5xx alarm (GreaterThanOrEqualToThreshold)."
  type        = number
  default     = 5

  validation {
    condition     = var.target_5xx_threshold >= 1 && var.target_5xx_threshold <= 100000 && floor(var.target_5xx_threshold) == var.target_5xx_threshold
    error_message = "target_5xx_threshold must be an integer between 1 and 100000."
  }
}

variable "target_5xx_period" {
  description = "Metric period in seconds for the target 5xx alarm. Must be a CloudWatch-valid period (10, 30, or a multiple of 60 up to 86400)."
  type        = number
  default     = 300

  validation {
    condition     = contains([10, 30], var.target_5xx_period) || (var.target_5xx_period % 60 == 0 && var.target_5xx_period >= 60 && var.target_5xx_period <= 86400)
    error_message = "target_5xx_period must be 10, 30, or a multiple of 60 between 60 and 86400 seconds."
  }
}

variable "target_5xx_evaluation_periods" {
  description = "Number of consecutive periods the target 5xx sum must breach before the alarm fires."
  type        = number
  default     = 2

  validation {
    condition     = var.target_5xx_evaluation_periods >= 1 && var.target_5xx_evaluation_periods <= 100 && floor(var.target_5xx_evaluation_periods) == var.target_5xx_evaluation_periods
    error_message = "target_5xx_evaluation_periods must be an integer between 1 and 100."
  }
}

# ---------------------------------------------------------------------------
# ALB load-balancer 5xx alarm (AWS/ApplicationELB HTTPCode_ELB_5XX_Count, Sum).
# Dimensioned by LoadBalancer only.
# ---------------------------------------------------------------------------

variable "elb_5xx_threshold" {
  description = "Count of load-balancer-generated HTTP 5xx responses in a period that triggers the ELB 5xx alarm (GreaterThanOrEqualToThreshold)."
  type        = number
  default     = 5

  validation {
    condition     = var.elb_5xx_threshold >= 1 && floor(var.elb_5xx_threshold) == var.elb_5xx_threshold
    error_message = "elb_5xx_threshold must be an integer greater than or equal to 1."
  }
}

variable "elb_5xx_period" {
  description = "Metric period in seconds for the ELB 5xx alarm. Must be a CloudWatch-valid period (10, 30, or a multiple of 60 up to 86400)."
  type        = number
  default     = 300

  validation {
    condition     = contains([10, 30], var.elb_5xx_period) || (var.elb_5xx_period % 60 == 0 && var.elb_5xx_period >= 60 && var.elb_5xx_period <= 86400)
    error_message = "elb_5xx_period must be 10, 30, or a multiple of 60 between 60 and 86400 seconds."
  }
}

variable "elb_5xx_evaluation_periods" {
  description = "Number of consecutive periods the ELB 5xx sum must breach before the alarm fires."
  type        = number
  default     = 2

  validation {
    condition     = var.elb_5xx_evaluation_periods >= 1 && var.elb_5xx_evaluation_periods <= 100 && floor(var.elb_5xx_evaluation_periods) == var.elb_5xx_evaluation_periods
    error_message = "elb_5xx_evaluation_periods must be an integer between 1 and 100."
  }
}

# ---------------------------------------------------------------------------
# ALB target response-time (latency) alarm
# (AWS/ApplicationELB TargetResponseTime, seconds, extended percentile).
# ---------------------------------------------------------------------------

variable "latency_alarm_statistic" {
  description = "Extended percentile statistic for the TargetResponseTime latency alarm (reflects tail latency rather than the average)."
  type        = string
  default     = "p95"

  validation {
    condition     = contains(["p90", "p95", "p99"], var.latency_alarm_statistic)
    error_message = "latency_alarm_statistic must be one of p90, p95, or p99."
  }
}

variable "latency_threshold_seconds" {
  description = "Target response time in seconds that triggers the latency alarm (GreaterThanOrEqualToThreshold)."
  type        = number
  default     = 2

  validation {
    condition     = var.latency_threshold_seconds >= 0
    error_message = "latency_threshold_seconds must be a non-negative number of seconds."
  }
}

variable "latency_alarm_period" {
  description = "Metric period in seconds for the latency alarm. Must be a CloudWatch-valid period (10, 30, or a multiple of 60 up to 86400)."
  type        = number
  default     = 60

  validation {
    condition     = contains([10, 30], var.latency_alarm_period) || (var.latency_alarm_period % 60 == 0 && var.latency_alarm_period >= 60 && var.latency_alarm_period <= 86400)
    error_message = "latency_alarm_period must be 10, 30, or a multiple of 60 between 60 and 86400 seconds."
  }
}

variable "latency_alarm_evaluation_periods" {
  description = "Number of consecutive periods TargetResponseTime must breach before the latency alarm fires."
  type        = number
  default     = 3

  validation {
    condition     = var.latency_alarm_evaluation_periods >= 1 && var.latency_alarm_evaluation_periods <= 100 && floor(var.latency_alarm_evaluation_periods) == var.latency_alarm_evaluation_periods
    error_message = "latency_alarm_evaluation_periods must be an integer between 1 and 100."
  }
}

# ---------------------------------------------------------------------------
# Optional SNS notification path (disabled by default).
# ---------------------------------------------------------------------------

variable "enable_sns" {
  description = "When true, create one SNS topic (no SSE at rest; TLS in transit) and attach it as the alarm action for every alarm. Off by default so DEV creates zero SNS resources and alarms have empty alarm_actions."
  type        = bool
  default     = false
}

variable "sns_notification_email" {
  description = "Email endpoint subscribed to the alarm SNS topic when enable_sns is true and this is non-empty. Operational configuration supplied via variable; never hardcoded and never a secret. Empty string creates the topic with no subscription."
  type        = string
  default     = ""
}
