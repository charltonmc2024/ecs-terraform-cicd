# Default-region AWS provider for the dev root.
# Credentials are supplied by the environment (IAM role / profile / env vars),
# never hardcoded here. An aliased us-east-1 provider is declared below for the
# security module's CLOUDFRONT-scoped WAFv2 web ACL.
provider "aws" {
  region = var.aws_region

  # Common tags applied to every taggable resource. These complement the
  # explicit per-resource Name tags and the var.tags passed into modules.
  default_tags {
    tags = {
      Project     = var.app_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = var.owner
    }
  }
}

# Aliased us-east-1 provider for the security module. A WAFv2 web ACL with
# scope = "CLOUDFRONT" MUST be created in us-east-1 regardless of the deployment
# region. The default provider above happens to resolve to us-east-1 in DEV
# (var.aws_region = "us-east-1"), but the security module is mapped to THIS
# explicit alias so the CLOUDFRONT-scoped resources stay correct even if a
# future environment sets a different default region. Same credentials/profile
# as the default provider (supplied by the environment), and the identical
# default_tags so resources created through the alias are tagged consistently.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = var.app_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = var.owner
    }
  }
}
