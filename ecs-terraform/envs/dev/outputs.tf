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
