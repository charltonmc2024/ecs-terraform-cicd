# ---------------------------------------------------------------------------
# Outputs — useful infrastructure references after apply
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------
output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

# ---------------------------------------------------------------------------
# CloudFront
# ---------------------------------------------------------------------------
output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name (use this or the custom domain to reach the app)"
  value       = aws_cloudfront_distribution.frontend.domain_name
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID — needed for cache invalidations during frontend deploys"
  value       = aws_cloudfront_distribution.frontend.id
}

# ---------------------------------------------------------------------------
# S3
# ---------------------------------------------------------------------------
output "frontend_bucket_name" {
  description = "S3 bucket name for the React frontend — CodeBuild uploads here"
  value       = aws_s3_bucket.frontend.id
}

output "frontend_bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.frontend.arn
}

# ---------------------------------------------------------------------------
# ALB
# ---------------------------------------------------------------------------
output "alb_dns_name" {
  description = "ALB DNS name"
  value       = aws_lb.ecs_alb.dns_name
}

# ---------------------------------------------------------------------------
# ECR
# ---------------------------------------------------------------------------
output "ecr_repository_url" {
  description = "ECR repository URL — used in CodeBuild to push and tag the backend image"
  value       = aws_ecr_repository.ecr_repo.repository_url
}

# ---------------------------------------------------------------------------
# ECS
# ---------------------------------------------------------------------------
output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.ecs_cluster.name
}

output "ecs_service_name" {
  description = "ECS service name — used in CodePipeline to trigger rolling deploys"
  value       = aws_ecs_service.ecs_service.name
}

# ---------------------------------------------------------------------------
# ACM
# ---------------------------------------------------------------------------
output "cloudfront_certificate_arn" {
  description = "ACM certificate ARN used by CloudFront (us-east-1)"
  value       = aws_acm_certificate_validation.cloudfront.certificate_arn
}

output "alb_certificate_arn" {
  description = "ACM certificate ARN used by the ALB HTTPS listener"
  value       = aws_acm_certificate_validation.alb.certificate_arn
}

# ---------------------------------------------------------------------------
# DynamoDB
# ---------------------------------------------------------------------------
output "dynamodb_users_table_name" {
  description = "DynamoDB users table name"
  value       = aws_dynamodb_table.users.name
}

output "dynamodb_tutors_table_name" {
  description = "DynamoDB tutors table name"
  value       = aws_dynamodb_table.tutors.name
}

output "dynamodb_courses_table_name" {
  description = "DynamoDB courses table name"
  value       = aws_dynamodb_table.courses.name
}

output "dynamodb_bookings_table_name" {
  description = "DynamoDB bookings table name"
  value       = aws_dynamodb_table.bookings.name
}

output "dynamodb_classes_table_name" {
  description = "DynamoDB classes table name"
  value       = aws_dynamodb_table.classes.name
}

# ---------------------------------------------------------------------------
# Application URL
# ---------------------------------------------------------------------------
output "application_url" {
  description = "Public HTTPS URL of the tutoring platform"
  value       = "https://${var.domain_name}"
}

# ---------------------------------------------------------------------------
# Route 53
# ---------------------------------------------------------------------------
output "route53_zone_id" {
  description = "Route 53 hosted zone ID"
  value       = aws_route53_zone.main.zone_id
}

output "route53_nameservers" {
  description = "Nameservers to set at your domain registrar after apply"
  value       = aws_route53_zone.main.name_servers
}
