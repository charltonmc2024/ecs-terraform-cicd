# Terraform Standards

## Current Scope

The only deployment root currently being implemented is:

`ecs-terraform/envs/dev/`

Do not create:

- `envs/staging/`
- `envs/prod/`

unless explicitly requested.

## Directory Structure

Reusable infrastructure:

`ecs-terraform/modules/`

Current root module:

`ecs-terraform/envs/dev/`

Remote-state bootstrap:

`ecs-terraform/bootstrap/`

## Modules

Current modules:

- network
- edge
- backend
- data
- cicd
- observability

Modules must remain reusable and must not contain unnecessary
development-specific configuration.

## No Hardcoding

Do not hardcode:

- AWS account IDs
- ARNs
- VPC IDs
- subnet IDs
- security group IDs
- ECR URLs
- generated resource identifiers

Use:

- Terraform variables
- locals
- resource references
- data sources
- module outputs

## Variables

Variables should:

- Have meaningful names
- Declare explicit types
- Include useful descriptions
- Include validation where appropriate

Development-specific values belong primarily in:

`envs/dev/terraform.tfvars`

## Outputs

Modules should expose only values required by another module,
the root module, CI/CD, or operators.

Examples:

- vpc_id
- public_subnet_ids
- private_subnet_ids
- alb_security_group_id
- ecs_security_group_id
- ecr_repository_url
- ecs_cluster_name
- ecs_service_name
- table_name
- cloudfront_distribution_id

## Naming

Use locals for derived names.

Preferred pattern:

`${var.app_name}-${var.environment}`

Avoid repeating naming logic across resources.

## Tags

Use common tags where AWS resources support them.

Recommended:

- Project
- Environment
- ManagedBy
- Owner

## State

The bootstrap configuration creates the remote-state infrastructure.

Bootstrap uses separate state from the main development environment.

Development state key:

`dev/terraform.tfstate`

Never commit:

- `*.tfstate`
- `*.tfstate.*`
- `.terraform/`

## Backend

The environment backend configuration belongs under:

`envs/dev/`

Do not attempt to create the backend S3 bucket from the same Terraform
state that depends on that backend.

## Providers

Configure AWS providers in the root environment:

`envs/dev/providers.tf`

Provider aliases should also be defined there.

Example:

- default AWS region
- `aws.us_east_1`

Child modules should receive provider configurations when required.

Do not place AWS credentials inside provider configuration.

## Terraform Workflow

Before committing:

`terraform fmt -recursive`

Before applying:

`terraform init`
`terraform validate`
`terraform plan`

Review the plan before:

`terraform apply`

## Resource Movement

When refactoring existing resources into modules, do not blindly
delete and recreate resources.

Review Terraform state and resource addresses.

Use Terraform state-aware refactoring such as `moved` blocks when
appropriate to prevent unnecessary destruction and recreation.

## Versions

Use compatible pinned Terraform and AWS provider versions.

Do not perform major version upgrades without reviewing compatibility.