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
