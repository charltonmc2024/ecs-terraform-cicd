# Input variables for the dev deployment root. These mirror the network
# module's inputs so values flow from terraform.tfvars through the root into
# the module call. The module's `tags` map is not mirrored here: the root
# assembles the common tag set (Project, Environment, ManagedBy, Owner) in
# main.tf, deriving the Owner value from `var.owner`.

variable "app_name" {
  description = "Application name used as the base for derived resource names (e.g. eruditiontx-app)."
  type        = string
}

variable "environment" {
  description = "Environment identifier used as the base for derived resource names (e.g. ecs-dev)."
  type        = string
}

variable "aws_region" {
  description = "AWS region the development infrastructure is deployed into."
  type        = string
}

variable "owner" {
  description = "Owner identifier applied as the Owner key in the common tag set (e.g. a team name)."
  type        = string
}

variable "vpc_cidr" {
  description = "IPv4 CIDR block for the VPC (/16 to /28)."
  type        = string
}

variable "public_subnet_cidr1" {
  description = "IPv4 CIDR block for the first public subnet, in the first availability zone."
  type        = string
}

variable "public_subnet_cidr2" {
  description = "IPv4 CIDR block for the second public subnet, in the second availability zone."
  type        = string
}

variable "private_subnet_cidr1" {
  description = "IPv4 CIDR block for the first private subnet, in the first availability zone."
  type        = string
}

variable "private_subnet_cidr2" {
  description = "IPv4 CIDR block for the second private subnet, in the second availability zone."
  type        = string
}

variable "enable_nat_gateway" {
  description = "When true, provision a NAT Gateway (and its Elastic IP) and add a default route from the private route table; disabled by default to avoid recurring cost in development."
  type        = bool
  default     = false
}

variable "enable_vpc_endpoints" {
  description = "When true, provision the S3 gateway VPC endpoint; disabled by default. (No DynamoDB endpoint: the database is external MongoDB Atlas.)"
  type        = bool
  default     = false
}

# Backend / application-layer inputs consumed by module "backend" (ECS Fargate app).

# MongoDB Atlas connection URI secret. The secret itself is created OUTSIDE Terraform
# (AWS Secrets Manager) and never stored in any committed file; only its ARN is passed
# here. Default null keeps the DEV plan free of secret resources until an ARN is set.
# When set, the backend module injects it into the container as MONGODB_URL and scopes
# the ECS execution role to read exactly that ARN.
variable "app_secret_arn" {
  description = "Optional AWS Secrets Manager (or SSM Parameter Store) ARN holding the MongoDB Atlas connection URI, injected into the container as MONGODB_URL. Default null leaves the DEV plan free of secret resources. Never store the URI itself in Terraform."
  type        = string
  default     = null
  sensitive   = true
}

variable "db_name" {
  description = "Main MongoDB database name for the FastAPI backend."
  type        = string
  default     = "teacher_student_db"

  validation {
    condition     = length(trimspace(var.db_name)) > 0
    error_message = "db_name must not be empty."
  }
}

variable "staff_admin_secret_arn" {
  description = "Optional AWS Secrets Manager ARN for the staff-admin MongoDB connection."
  type        = string
  default     = null
  sensitive   = true
}

variable "staff_admin_db_name" {
  description = "Staff-admin MongoDB database name."
  type        = string
  default     = null

  validation {
    condition = (
      var.staff_admin_db_name == null
      ? true
      : length(trimspace(var.staff_admin_db_name)) > 0
    )
    error_message = "staff_admin_db_name must not be empty when provided."
  }
}

variable "container_port" {
  description = "TCP port the application container listens on; used by the task definition port mapping, target group, and ECS security group ingress."
  type        = number
  default     = 3000
}

variable "health_check_path" {
  description = "HTTP path the ALB target group health check requests so the ALB only routes to healthy tasks."
  type        = string
  default     = "/"
}

variable "image_tag" {
  # BOOTSTRAP PLACEHOLDER: "latest" is only a placeholder so validate/plan work
  # before any real image exists in ECR. It is NOT a real deployable image. Before
  # running application tasks we will push a real immutable Git-SHA image and update
  # image_tag (together with desired_count = 1 and min_capacity = 1) in one change.
  description = "Application image tag the ECS task definition references. A real deploy overrides this with an immutable tag (e.g. a Git SHA); the default \"latest\" is a bootstrap placeholder only so validate/plan work before an image exists."
  type        = string
  default     = "latest"
}

# First-deployment bootstrap: desired_count and min_capacity are surfaced at the
# root so DEV can start with ZERO tasks before any real image exists in ECR
# (avoiding tasks that would crash-loop pulling a non-existent image). Validation
# allows zero. After a real Git-SHA image is pushed, these move to 1 alongside a
# real image_tag. The backend module keeps its own defaults (1/1); the root only
# overrides them for the bootstrap window.

variable "desired_count" {
  description = "Desired number of running ECS service tasks. Set to 0 for the first-deployment bootstrap (before a real image exists), then raised to 1 with a real image_tag."
  type        = number
  default     = 1

  validation {
    condition     = var.desired_count >= 0
    error_message = "desired_count must be zero or greater (zero is allowed for the first-deployment bootstrap)."
  }
}

variable "min_capacity" {
  description = "Autoscaling floor (minimum ECS tasks). Set to 0 for the first-deployment bootstrap, then raised to 1 with a real image_tag."
  type        = number
  default     = 1

  validation {
    condition     = var.min_capacity >= 0
    error_message = "min_capacity must be zero or greater (zero is allowed for the first-deployment bootstrap)."
  }
}

# Observability / log-retention inputs.

# Passed into module.backend to set the ECS application log group retention. DEV
# uses 7 days as the cost-optimized default (reducing the backend module's own
# 14-day default). The ECS app log group remains owned by the backend module.
variable "log_retention_days" {
  description = "CloudWatch Logs retention in days for the backend ECS application log group. DEV default is 7 (cost-optimized); the ECS log group stays owned by the backend module and is reused (not recreated) by the observability module."
  type        = number
  default     = 7

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a CloudWatch Logs-supported retention value (e.g. 1, 3, 5, 7, 14, 30, ...). DEV uses 7."
  }
}

# Consumed by module.observability. Off by default so DEV creates zero SNS
# resources and every alarm has an empty action list.
variable "enable_observability_sns" {
  description = "When true, the observability module creates one SNS topic (no SSE at rest; TLS in transit) and wires it as the action for every alarm. Off by default in DEV."
  type        = bool
  default     = false
}

# Email endpoint subscribed to the alarm SNS topic when enable_observability_sns
# is true and this is non-empty. Operational configuration, never a secret; empty
# string creates the topic with no subscription.
variable "observability_sns_email" {
  description = "Email endpoint subscribed to the alarm SNS topic when enable_observability_sns is true and this is non-empty. Not a secret; empty by default."
  type        = string
  default     = ""
}

# ECR security: immutable image tags for reproducible deployments.
variable "image_tag_mutability" {
  description = "Controls whether ECR image tags can be overwritten."
  type        = string
  default     = "IMMUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be MUTABLE or IMMUTABLE."
  }
}

# -----------------------------------------------------------------------------
# Security module inputs (consumed by module.security).
#
# Every optional billable security capability is OFF by default so the DEV
# baseline creates zero additional security resources. The security module is
# mapped to the aws.us_east_1 provider alias in main.tf (CLOUDFRONT-scoped WAF
# must live in us-east-1).
# -----------------------------------------------------------------------------

variable "enable_waf" {
  description = "When true, module.security creates the CLOUDFRONT WAFv2 web ACL and the CloudFront distribution is associated with it. Off by default in DEV."
  type        = bool
  default     = false
}

variable "enable_cloudtrail" {
  description = "When true, module.security creates a management-events-only CloudTrail trail and its S3 log bucket (unless an existing trail is reused). Off by default in DEV."
  type        = bool
  default     = false
}

variable "enable_security_alerts" {
  description = "When true, module.security creates the EventBridge security-event rules and the SNS security-alerts topic they target. Off by default in DEV."
  type        = bool
  default     = false
}

variable "security_alerts_email" {
  description = "Email endpoint subscribed to the SNS security-alerts topic when enable_security_alerts is true and this is non-empty. Operational configuration, never a secret; empty by default (topic with no subscription)."
  type        = string
  default     = ""
}
