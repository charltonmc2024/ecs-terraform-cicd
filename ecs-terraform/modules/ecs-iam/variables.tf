variable "app_name" {
  description = "Application name used in IAM role naming."
  type        = string
}

variable "environment" {
  description = "Deployment environment."
  type        = string
}

variable "tags" {
  description = "Tags applied to IAM roles."
  type        = map(string)
  default     = {}
}

variable "ecs_permissions_boundary_arn" {
  description = "Permissions boundary ARN for ECS execution and task roles."
  type        = string
}

variable "api_mongodb_secret_arn" {
  description = "ARN of the FastAPI MongoDB connection secret."
  type        = string
  default     = null
  sensitive   = true
}

variable "api_key_secret_arn" {
  description = "ARN of the FastAPI API key secret."
  type        = string
  default     = null
  sensitive   = true
}

variable "api_execution_secret_policy_arn" {
  description = "ARN of the administrator-managed FastAPI secret-read policy."
  type        = string
  default     = null
}
