variable "app_name" {
  description = "Application name."
  type        = string
}

variable "environment" {
  description = "Deployment environment."
  type        = string
}

variable "tags" {
  description = "Tags for ECS IAM resources."
  type        = map(string)
  default     = {}
}

variable "ecs_permissions_boundary_arn" {
  description = "Permissions boundary for ECS roles."
  type        = string
}

variable "api_mongodb_secret_arn" {
  description = "FastAPI MongoDB secret ARN."
  type        = string
  default     = null
  sensitive   = true
}

variable "api_key_secret_arn" {
  description = "FastAPI API key secret ARN."
  type        = string
  default     = null
  sensitive   = true
}

variable "aws_region" {
  description = "AWS region for administrator-managed IAM."
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "AWS CLI profile authorized to manage ECS IAM roles."
  type        = string
}

variable "aws_account_id" {
  description = "Expected AWS account ID."
  type        = string
  default     = "691778449106"
}
