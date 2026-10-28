# variables.tf
#
# Input variables for the reusable security module. The module is
# environment-independent: it accepts typed, validated inputs and derives every
# resource name from local.name_prefix. No AWS account IDs, ARNs, or region
# strings are hardcoded here. Region is NOT a module input — it comes from the
# AWS provider the Dev_Root maps in (the aws.us_east_1 alias), which this module
# inherits.
#
# This task (scaffold) declares only the naming and tag inputs that main.tf
# references. The feature-toggle and tuning inputs (enable_waf, enable_cloudtrail,
# enable_security_alerts, waf_*, detective toggles, and the rest) are added in
# the variables task alongside the files that consume them, so no variable is
# declared before a resource uses it.

variable "app_name" {
  description = "Application name used as the first segment of the resource name prefix (e.g. eruditiontx-app)."
  type        = string

  validation {
    condition     = length(trimspace(var.app_name)) > 0
    error_message = "app_name must be a non-empty, non-whitespace string."
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
# AWS WAFv2 (optional, default OFF). When enable_waf is true the module creates
# one CLOUDFRONT-scope web ACL; the cost-optimized baseline is the AWS Managed
# Common Rule Set plus one rate-based rule, both starting in COUNT mode so no
# legitimate traffic is blocked before false-positive evaluation. Additional
# managed groups (e.g. Known Bad Inputs) are configurable and default OFF.
# ---------------------------------------------------------------------------

variable "enable_waf" {
  description = "When true, create the WAFv2 CLOUDFRONT web ACL and associate it with the CloudFront distribution via the edge web_acl_id input. Off by default so DEV creates zero WAF resources and the distribution has no web ACL association."
  type        = bool
  default     = false
}

variable "waf_default_action" {
  description = "Default action for requests that match no WAF rule: 'allow' (default) or 'block'. The cost-optimized DEV baseline keeps 'allow' so only rule matches are evaluated."
  type        = string
  default     = "allow"

  validation {
    condition     = contains(["allow", "block"], var.waf_default_action)
    error_message = "waf_default_action must be either \"allow\" or \"block\"."
  }
}

variable "waf_rate_limit" {
  description = "Request-rate limit for the WAF rate-based rule, aggregated per source IP over the fixed WAFv2 5-minute (300-second) window. DEV default is 2000."
  type        = number
  default     = 2000

  validation {
    condition     = var.waf_rate_limit >= 100 && var.waf_rate_limit <= 2000000000 && floor(var.waf_rate_limit) == var.waf_rate_limit
    error_message = "waf_rate_limit must be an integer between 100 and 2000000000 inclusive."
  }
}

variable "waf_common_rule_set_mode" {
  description = "Enforcement mode for the AWS Managed Common Rule Set: 'Count_Mode' (default) counts and labels matches without blocking; 'Block_Mode' lets the managed group's own block actions apply. Start in Count_Mode and transition to Block_Mode only after evaluating false positives."
  type        = string
  default     = "Count_Mode"

  validation {
    condition     = contains(["Count_Mode", "Block_Mode"], var.waf_common_rule_set_mode)
    error_message = "waf_common_rule_set_mode must be either \"Count_Mode\" or \"Block_Mode\"."
  }
}

variable "waf_rate_based_rule_mode" {
  description = "Enforcement mode for the WAF rate-based rule: 'Count_Mode' (default) counts matches without blocking; 'Block_Mode' blocks source IPs that exceed waf_rate_limit. Start in Count_Mode and transition to Block_Mode only after evaluating false positives."
  type        = string
  default     = "Count_Mode"

  validation {
    condition     = contains(["Count_Mode", "Block_Mode"], var.waf_rate_based_rule_mode)
    error_message = "waf_rate_based_rule_mode must be either \"Count_Mode\" or \"Block_Mode\"."
  }
}

variable "enable_known_bad_inputs" {
  description = "When true, add the AWS Managed Known Bad Inputs rule group to the web ACL (only when enable_waf is also true). Off by default so the cost-optimized baseline stays Common Rule Set plus the rate-based rule."
  type        = bool
  default     = false
}

variable "waf_known_bad_inputs_mode" {
  description = "Enforcement mode for the optional Known Bad Inputs rule group: 'Count_Mode' (default) or 'Block_Mode'. Applies only when enable_known_bad_inputs is true."
  type        = string
  default     = "Count_Mode"

  validation {
    condition     = contains(["Count_Mode", "Block_Mode"], var.waf_known_bad_inputs_mode)
    error_message = "waf_known_bad_inputs_mode must be either \"Count_Mode\" or \"Block_Mode\"."
  }
}

# ---------------------------------------------------------------------------
# AWS CloudTrail (optional, default OFF). A suitable existing account/org trail
# that is both configured for management-event coverage and actively logging
# (IsLogging = true) should be reused instead of creating a new trail. A new
# management-events-only trail is created only when enable_cloudtrail is true
# AND reuse_existing_trail is false.
# ---------------------------------------------------------------------------

variable "enable_cloudtrail" {
  description = "When true, create a management-events-only CloudTrail trail and its backing S3 bucket (unless reuse_existing_trail is true). Off by default so DEV creates no trail or trail bucket."
  type        = bool
  default     = false
}

variable "reuse_existing_trail" {
  description = "When true, reuse a suitable existing account or organization trail (one that covers management events AND is actively logging) instead of creating a new trail; no trail resources are created even if enable_cloudtrail is true."
  type        = bool
  default     = false
}

variable "cloudtrail_retention_days" {
  description = "Number of days trail log objects are retained in the trail S3 bucket before expiry via a lifecycle rule. Bounded so no trail object is retained indefinitely. DEV default is 365."
  type        = number
  default     = 365

  validation {
    condition     = var.cloudtrail_retention_days >= 1 && var.cloudtrail_retention_days <= 365 && floor(var.cloudtrail_retention_days) == var.cloudtrail_retention_days
    error_message = "cloudtrail_retention_days must be an integer between 1 and 365 inclusive."
  }
}

# ---------------------------------------------------------------------------
# Security alerts: EventBridge security-event rules + SNS topic (optional,
# default OFF). The single enable_security_alerts toggle gates both the
# EventBridge rules (the detector) and the SNS topic (the delivery path).
# ---------------------------------------------------------------------------

variable "enable_security_alerts" {
  description = "When true, create the targeted EventBridge security-event rules on the default bus and the SNS security-alerts topic they target. Off by default so DEV creates zero EventBridge or SNS security resources."
  type        = bool
  default     = false
}

variable "security_alerts_email" {
  description = "Email endpoint subscribed to the SNS security-alerts topic when enable_security_alerts is true and this is non-empty. Operational configuration supplied via variable, never a secret; empty string (default) creates the topic with no subscription."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Optional account-wide detective services (gating surface only; all default
# OFF and deferred for DEV per the security review). These toggles exist so a
# future environment can enable a service without redesigning the module; no
# customer-managed KMS key variable is declared (AWS-managed encryption is
# sufficient for DEV).
# ---------------------------------------------------------------------------

variable "enable_guardduty" {
  description = "When true, enable Amazon GuardDuty (account-wide, billable). Off by default and deferred for DEV."
  type        = bool
  default     = false
}

variable "enable_config" {
  description = "When true, enable AWS Config recording (account-wide, billable). Off by default and deferred for DEV."
  type        = bool
  default     = false
}

variable "enable_security_hub" {
  description = "When true, enable AWS Security Hub (account-wide, billable). Off by default and deferred for DEV."
  type        = bool
  default     = false
}

variable "enable_inspector_enhanced" {
  description = "When true, enable Amazon Inspector enhanced scanning (account-wide, billable). Off by default and deferred for DEV; ECR basic scan-on-push is retained by the backend module."
  type        = bool
  default     = false
}
