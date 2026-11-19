terraform {
  backend "s3" {
    bucket       = "eruditiontx-app-ecs-dev-tfstate-691778449106"
    key          = "iam-policies/ecs-roles/dev/terraform.tfstate"
    region       = "us-east-1"
    profile      = "charltonecs"
    encrypt      = true
    use_lockfile = true
  }
}
