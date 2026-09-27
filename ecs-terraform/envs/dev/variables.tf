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
  description = "When true, provision S3 and DynamoDB gateway VPC endpoints; disabled by default."
  type        = bool
  default     = false
}

# Data-layer inputs consumed by module "data" (DynamoDB App_Table).

variable "enable_point_in_time_recovery" {
  description = "When true, enable DynamoDB point-in-time recovery on the App_Table; PITR is cost-bearing but enabled by default as the baseline recovery mechanism."
  type        = bool
  default     = true
}

variable "deletion_protection_enabled" {
  description = "When true, protect the DynamoDB App_Table from deletion; disabled by default in development so the table can be torn down freely."
  type        = bool
  default     = false
}

# Backend / application-layer inputs consumed by module "backend" (ECS Fargate app).

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
  description = "Application image tag the ECS task definition references. A real deploy overrides this with an immutable tag (e.g. a Git SHA); the default keeps validate/plan working."
  type        = string
  default     = "latest"
}
