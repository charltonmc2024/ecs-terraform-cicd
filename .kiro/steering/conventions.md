# Project Conventions

## Current Scope

Focus on completing:

`envs/dev`

Do not create staging or production infrastructure unless explicitly requested.

## Terraform Naming

Use:

`snake_case`

for Terraform:

- resources
- variables
- locals
- outputs

Use meaningful names.

Avoid names such as:

- resource1
- test123
- thing
- temp

## AWS Naming

Use a consistent resource naming pattern.

Preferred concept:

`${app_name}-${environment}-${resource}`

Example:

`eruditiontx-dev-ecs-service`

Use locals rather than repeating naming logic.

## Terraform Files

Use descriptive filenames.

Examples:

- main.tf
- variables.tf
- outputs.tf
- nat.tf
- endpoints.tf
- security-groups.tf
- ecs.tf
- alb.tf
- iam.tf
- cloudfront.tf
- logs.tf
- autoscaling.tf

Remember that Terraform loads all `.tf` files in the same directory
as one module.

File separation exists primarily for readability.

## Comments

Comments should explain why something exists.

Good:

`# Internal ALB is accessed through CloudFront VPC Origin.`

Avoid comments that merely repeat Terraform syntax.

## Git

Never commit:

- `.terraform/`
- `*.tfstate`
- `*.tfstate.*`
- credentials
- private keys
- secrets
- local files containing secrets

Commit the Terraform dependency lock file for deployable root modules
when appropriate.

## Validation

Before committing Terraform:

`terraform fmt -recursive`

Then validate the active development root.

Before infrastructure changes:

`terraform plan`

Review the plan before applying.

## Cost

Prefer cost-conscious development resources.

Do not create:

- unnecessary NAT Gateways
- oversized compute
- excessive log retention
- unnecessary endpoints
- duplicate CI/CD systems
- unnecessary managed services

when a simpler solution satisfies the requirement.

## Architecture Stability

Follow the architecture defined in `architecture.md`.

Do not redesign working infrastructure without a clear requirement.

If an architectural change is necessary, explain:

1. Why the change is needed
2. What resources change
3. Cost impact
4. Security impact
5. Terraform/state impact

before implementing a destructive or significant change.

## Development Priority

Finish the development environment end-to-end before expanding the
project to additional environments.

Current implementation priority:

1. Network
2. Data
3. Backend
4. Edge
5. Jenkins CI/CD
6. Observability