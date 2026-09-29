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

# The data module owns the single-table DynamoDB App_Table. DynamoDB is a regional,
# fully-managed service, so this module has no network dependency. It inherits the AWS
# provider (region + default_tags) from the dev root; no aws_region is passed in.
# deletion_protection_enabled is passed explicitly because deletion protection is an
# environment-level choice that must be visible at the dev root (resolves to false in dev).
module "data" {
  source = "../../modules/data"

  app_name                      = var.app_name
  environment                   = var.environment
  enable_point_in_time_recovery = var.enable_point_in_time_recovery
  deletion_protection_enabled   = var.deletion_protection_enabled

  tags = {
    Project     = var.app_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Owner       = var.owner
  }
}
# The backend module owns the application runtime (ECS Fargate, internal ALB, ECR)
# and the CloudFront VPC Origin edge entry point. It consumes network outputs
# (vpc_id, private_subnet_ids) and data outputs (dynamodb_table_name/arn) — never
# literals (R14.5) — and inherits the AWS provider (region + default_tags) from the
# dev root; no aws_region is passed in. Sizing, autoscaling, and log retention use
# module defaults for cost-conscious development.
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

  vpc_id              = module.network.vpc_id
  private_subnet_ids  = module.network.private_subnet_ids
  dynamodb_table_name = module.data.dynamodb_table_name
  dynamodb_table_arn  = module.data.dynamodb_table_arn

  container_port    = var.container_port
  health_check_path = var.health_check_path
  image_tag         = var.image_tag
}

# The edge module owns the public entry point: the private S3 frontend bucket,
# Origin Access Control, the CloudFront VPC Origin, and the CloudFront
# distribution. It consumes only the internal ALB identifiers from the backend
# module (alb_arn to build the VPC Origin, alb_dns_name as the API origin
# domain) — never literals — preserving the network/data -> backend -> edge
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
