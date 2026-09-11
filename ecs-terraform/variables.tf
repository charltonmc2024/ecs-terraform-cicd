variable "app_name" {
  description = "My ECS Project APP Name"
  type        = string
  default     = "eruditiontx-app"
}

variable "vpc_name" {
  description = "My ECS VPC Name"
  type        = string
  default     = "ecs-vpc"
}


variable "environment" {
  description = "My ECS Project Environmet"
  type        = string
  default     = "ecs-dev"

}
variable "aws_region" {
  description = "My ECS Region"
  type        = string
  default     = "us-east-1"
}


variable "vpc_cidr" {
  description = "My ECS VPC CIDR Block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr1" {
  description = "Public Subnet CIDR 1"
  type        = string
  default     = "10.0.1.0/24"
}

variable "public_subnet_cidr2" {
  description = "Public Subnet CIDR 2"
  type        = string
  default     = "10.0.3.0/24"
}

variable "private_subnet_cidr1" {
  description = "Private Subnet CIDR 1"
  type        = string
  default     = "10.0.2.0/24"
}

variable "private_subnet_cidr2" {
  description = "Private Subnet CIDR 2"
  type        = string
  default     = "10.0.4.0/24"
}

variable "ecs_task_cpu" {
  description = "CPU Units for ECS Fagate Task "
  type        = number
  default     = 512
}


variable "ecs_task_memory" {
  description = "Memory Units for ECS Fagate Task "
  type        = number
  default     = 1024
}

variable "container_port" {
  description = "Container Port"
  type        = number
  default     = 80
}

variable "health_check_path" {
  description = "HTTP path used by the ALB to check ECS task health"
  type        = string
  default     = "/"
}

variable "ecs_desired_task_count" {
  description = "Number of ECS Tasks to run"
  type        = number
  default     = 1

  validation {
    condition     = var.ecs_desired_task_count >= 0
    error_message = "Desired Task Count must be positive."
  }
}