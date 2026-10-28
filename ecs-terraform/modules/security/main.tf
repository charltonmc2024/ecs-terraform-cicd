# main.tf
#
# Reusable security module for the Erudition Solution development environment.
# It adds a cross-cutting, cost-optimized security baseline over the existing
# network -> backend -> edge stack. Every billable control it owns is optional
# and defaults OFF (enable_waf, enable_cloudtrail, enable_security_alerts, and
# the detective-service toggles), so the module's additional baseline cost is
# $0 until an operator explicitly enables a capability. The capabilities are an
# optional WAFv2 CLOUDFRONT web ACL, an optional management-events CloudTrail
# trail, optional EventBridge security-event rules, and an optional SNS
# security-alerts topic (added by their own files in later tasks).
#
# Following the 04-edge / 06-observability convention, the module's terraform {}
# version block and the locals { name_prefix } block live at the top of this
# main file rather than in a separate versions.tf / locals.tf, keeping
# organizational-only files out of the module.
#
# This module declares NO `provider` block and NO `backend` block: it inherits
# the AWS provider from the Dev_Root at ecs-terraform/envs/dev/. Because a WAFv2
# CLOUDFRONT-scope web ACL must live in us-east-1, the Dev_Root maps the
# aws.us_east_1 provider alias into this module explicitly
# (providers = { aws = aws.us_east_1 }); the module itself names no region.

terraform {
  required_version = "~> 1.16.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.67.0, < 7.0.0"
    }
  }
}

# Single naming base for every security resource name and Name tag; the prefix
# is derived once here and never recomputed inline elsewhere in the module.
locals {
  name_prefix = "${var.app_name}-${var.environment}"
}

# Account id used to scope resource policies (SNS topic policy, CloudTrail S3
# bucket policy) with an aws:SourceAccount condition, so no AWS account id is
# ever a hardcoded literal. Consumed by sns.tf / cloudtrail.tf in later tasks.
data "aws_caller_identity" "current" {}
