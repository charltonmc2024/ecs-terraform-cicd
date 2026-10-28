# outputs.tf
#
# Minimal output surface: only values a concrete downstream consumer (the
# Dev_Root, operators) needs. Every output is null-safe when its feature is
# disabled — each optional resource is count-gated, so its attribute is read
# through one(resource[*].attr), which returns the single value when the
# resource exists (count = 1) and null when it does not (count = 0), never an
# invalid-index error. No output carries or derives from a secret value
# (no MongoDB URI, no credentials, no secret ARNs).

# WAFv2 web ACL ARN, consumed by the Dev_Root to wire the edge module's
# optional web_acl_id (Task 9). Null when enable_waf is false, so the edge
# distribution receives null and has no web ACL association.
output "web_acl_arn" {
  description = "ARN of the CLOUDFRONT-scope WAFv2 web ACL, or null when enable_waf is false. Consumed by the Dev_Root to associate the CloudFront distribution via the edge web_acl_id input."
  value       = var.enable_waf ? one(aws_wafv2_web_acl.this[*].arn) : null
}

# SNS security-alerts topic ARN. Null when enable_security_alerts is false.
# Operators use it to locate/confirm the topic; no secret value.
output "security_alerts_topic_arn" {
  description = "ARN of the SNS security-alerts topic, or null when enable_security_alerts is false."
  value       = one(aws_sns_topic.security_alerts[*].arn)
}

# CloudTrail new-trail outputs. Both are null unless a NEW trail was created
# (enable_cloudtrail = true AND reuse_existing_trail = false); they stay null
# when CloudTrail is disabled or an existing trail is reused.
output "cloudtrail_bucket_name" {
  description = "Name of the CloudTrail log S3 bucket, or null when no new trail is created (disabled or an existing trail is reused). Lets operators locate the log bucket."
  value       = one(aws_s3_bucket.trail[*].bucket)
}

output "cloudtrail_trail_arn" {
  description = "ARN of the new management-events CloudTrail trail, or null when no new trail is created (disabled or an existing trail is reused)."
  value       = one(aws_cloudtrail.this[*].arn)
}
