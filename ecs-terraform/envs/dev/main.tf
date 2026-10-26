# Dev deployment root wiring. This root module is the single source of truth
# for the development environment; it calls the reusable network module and
# passes values sourced from terraform.tfvars.

module "network" {
  source = "../../modules/network"

  app_name             = var.app_name
  environment          = var.environment
  aws_region           = var.aws_region
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidr1  = var.public_subnet_cidr1
  public_subnet_cidr2  = var.public_subnet_cidr2
  private_subnet_cidr1 = var.private_subnet_cidr1
  private_subnet_cidr2 = var.private_subnet_cidr2
  enable_nat_gateway   = var.enable_nat_gateway
  enable_vpc_endpoints = var.enable_vpc_endpoints

  # Common tag set applied uniformly across module resources. Owner is derived
  # from var.owner so the module stays environment-independent.
  tags = {
    Project     = var.app_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Owner       = var.owner
  }
}

# The application database is MongoDB Atlas (M0 free tier for dev), provisioned
# OUTSIDE Terraform via the Atlas console. There is no Terraform data module: Atlas
# is an external managed service, so no AWS database resource is created here. ECS
# tasks reach Atlas over the NAT Gateway's stable egress IP (Atlas M0 has no VPC
# peering/PrivateLink), and the connection URI is injected from AWS Secrets Manager
# (see module "backend" app_secret_arn below).

# The backend module owns the application runtime (ECS Fargate, internal ALB, ECR)
# and the CloudFront VPC Origin edge entry point. It consumes network outputs
# (vpc_id, private_subnet_ids) — never literals (R14.5) — and inherits the AWS
# provider (region + default_tags) from the dev root; no aws_region is passed in.
# Sizing, autoscaling, and log retention use module defaults for cost-conscious
# development. The MongoDB connection string is supplied out of band via
# app_secret_arn (Secrets Manager) and injected into the task as MONGODB_URL.
module "backend" {
  source = "../../modules/backend"

  app_name    = var.app_name
  environment = var.environment
  tags = {
    Project     = var.app_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Owner       = var.owner
  }

  vpc_id             = module.network.vpc_id
  private_subnet_ids = module.network.private_subnet_ids

  container_port       = var.container_port
  health_check_path    = var.health_check_path
  image_tag            = var.image_tag
  image_tag_mutability = var.image_tag_mutability
  # MongoDB Atlas connection URI, injected into the container as MONGODB_URL from
  # AWS Secrets Manager. Default null leaves the DEV plan free of secret resources;
  # the secret is created out of band (never in Terraform) and its ARN supplied here.
  app_secret_arn = var.app_secret_arn
  db_name        = var.db_name

  staff_admin_secret_arn = var.staff_admin_secret_arn
  staff_admin_db_name    = var.staff_admin_db_name

  # DEV log retention set to 7 days (cost-optimized). The ECS application log
  # group stays owned by the backend module; observability reuses it, never
  # recreates it.
  log_retention_days = var.log_retention_days

  # First-deployment bootstrap: start with zero tasks and a zero autoscaling floor
  # until a real Git-SHA image exists in ECR (image_tag = "latest" is a placeholder).
  desired_count = var.desired_count
  min_capacity  = var.min_capacity
}

# The edge module owns the public entry point: the private S3 frontend bucket,
# Origin Access Control, the CloudFront VPC Origin, and the CloudFront
# distribution. It consumes only the internal ALB identifiers from the backend
# module (alb_arn to build the VPC Origin, alb_dns_name as the API origin
# domain) — never literals — preserving the network -> backend -> edge
# dependency direction. alb_http_port uses the module default (80), so it is not
# passed explicitly.
module "edge" {
  source = "../../modules/edge"

  app_name    = var.app_name
  environment = var.environment
  tags = {
    Project     = var.app_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Owner       = var.owner
  }

  alb_arn      = module.backend.alb_arn
  alb_dns_name = module.backend.alb_dns_name
}

# The observability module is a cross-cutting, observe-only monitor of the already
# deployed stack. It OWNS only CloudWatch alarms, one dashboard, and an optional
# default-off SNS path; it creates no application resource and declares no ECS log
# group (the backend owns it). It consumes identifiers ONLY from other modules'
# outputs (never literals), preserving the network -> backend -> edge direction;
# nothing references the observability module back, so there is no cycle. The
# CloudFront VPC Origin / S3 / ALB / ECS Fargate / MongoDB Atlas architecture is
# unchanged by wiring this module in.
module "observability" {
  source = "../../modules/observability"

  app_name    = var.app_name
  environment = var.environment
  tags = {
    Project     = var.app_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Owner       = var.owner
  }

  # CloudWatch dimension values and the backend-owned ECS log group name, sourced
  # from backend outputs (ARN suffixes for ALB/target-group metrics) — never literals.
  ecs_cluster_name        = module.backend.ecs_cluster_name
  ecs_service_name        = module.backend.ecs_service_name
  alb_arn_suffix          = module.backend.alb_arn_suffix
  target_group_arn_suffix = module.backend.target_group_arn_suffix
  ecs_log_group_name      = module.backend.ecs_log_group_name

  # CloudFront dashboard widgets are optional and off by default in DEV; the
  # distribution id is supplied from the edge module for when they are enabled.
  cloudfront_distribution_id = module.edge.cloudfront_distribution_id

  # Optional SNS notifications: disabled by default in DEV (no SNS resources, empty
  # alarm actions). Email endpoint is operational config supplied via variable.
  enable_sns             = var.enable_observability_sns
  sns_notification_email = var.observability_sns_email
}
