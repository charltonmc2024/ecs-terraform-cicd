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

Do not create outputs merely because a resource has an ID or ARN.

Examples, when required by downstream consumers:

- vpc_id
- public_subnet_ids
- private_subnet_ids
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

### Clean-Slate Refactoring

The current modular architecture is a clean-slate implementation.

Previous application infrastructure was intentionally removed and
legacy Terraform files may remain in the repository temporarily for
reference.

Do not create `moved` blocks or perform Terraform state migration for
legacy application resources unless explicitly requested.

The current Terraform source of truth is:

- `ecs-terraform/modules/`
- `ecs-terraform/envs/dev/`

Legacy Terraform files outside these locations are reference-only.

Do not modify, import, migrate, or use legacy Terraform resources as
the implementation source unless explicitly requested.

Before deployment, verify that the active remote state does not contain
stale records for previously deleted application resources.