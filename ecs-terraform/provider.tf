terraform {

  required_version = "~>1.16.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~>6.62"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.app_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = "Charlton Cagigas"
    }
  }
}

# CloudFront ACM certificates must exist in us-east-1 regardless of the application region.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = var.app_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = "Charlton Cagigas"
    }
  }
}
