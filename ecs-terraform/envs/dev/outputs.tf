# Re-export the network module's outputs from the dev root so operators,
# downstream modules, and CI/CD can consume network resource identifiers
# without reaching into the module internals.

output "vpc_id" {
  description = "ID of the VPC created by the network module."
  value       = module.network.vpc_id
}

output "public_subnet_ids" {
  description = "IDs of the two public subnets (AZ a and AZ b)."
  value       = module.network.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs of the two private subnets (AZ a and AZ b) where ECS tasks run."
  value       = module.network.private_subnet_ids
}

output "nat_gateway_id" {
  description = "ID of the NAT Gateway when enable_nat_gateway is true, otherwise null."
  value       = module.network.nat_gateway_id
}

# Re-export the data module's DynamoDB App_Table identifiers so the backend module,
# CI/CD, and operators can reference the table without reaching into module internals.

output "dynamodb_table_name" {
  description = "Name of the DynamoDB App_Table created by the data module."
  value       = module.data.dynamodb_table_name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB App_Table, used to build IAM policies for table access."
  value       = module.data.dynamodb_table_arn
}

output "dynamodb_table_id" {
  description = "ID of the DynamoDB App_Table created by the data module."
  value       = module.data.dynamodb_table_id
}

# Re-export the backend module's minimized output surface. These identifiers are
# consumed by CI/CD (image push and ECS deployment) and by 04-edge, which builds
# the CloudFront distribution over the internal ALB via the VPC Origin.

output "ecr_repository_url" {
  description = "URL of the ECR repository that CI/CD pushes the application image to."
  value       = module.backend.ecr_repository_url
}

output "alb_dns_name" {
  description = "DNS name of the internal ALB, consumed by 04-edge as the CloudFront origin."
  value       = module.backend.alb_dns_name
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster, used by CI/CD to target ECS deployments."
  value       = module.backend.ecs_cluster_name
}

output "ecs_service_name" {
  description = "Name of the ECS service, used by CI/CD to trigger and verify deployments."
  value       = module.backend.ecs_service_name
}

# Re-export the edge module's minimal output surface so operators and CI/CD can
# reach the environment and upload frontend assets. The VPC Origin id, OAC id,
# bucket ARN, and distribution ARN are intentionally NOT re-exported.

output "cloudfront_domain_name" {
  description = "Default *.cloudfront.net domain name of the CloudFront distribution, used to reach the environment."
  value       = module.edge.cloudfront_domain_name
}

output "cloudfront_distribution_id" {
  description = "ID of the CloudFront distribution, used by operators and CI/CD (for example cache invalidations)."
  value       = module.edge.cloudfront_distribution_id
}

output "frontend_bucket_name" {
  description = "Name of the private S3 frontend bucket, used by CI/CD to upload the compiled frontend assets."
  value       = module.edge.frontend_bucket_name
}
