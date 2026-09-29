# Terraform Standards

## Current Scope

The only deployment root currently being implemented is:

`ecs-terraform/envs/dev/`

Do not create:

- `envs/staging/`
- `envs/prod/`

unless explicitly requested.

Reusable modules should remain environment-independent where practical so future environments can consume them without redesigning the core module architecture.

Do not create speculative staging or production resources for future compatibility.

---

## Directory Structure

Reusable infrastructure:

`ecs-terraform/modules/`

Current root module:

`ecs-terraform/envs/dev/`

Remote-state bootstrap:

`ecs-terraform/bootstrap/`

The root environment composes reusable modules and provides environment-specific configuration.

---

## Modules

Current modules:

- network
- data
- backend
- edge
- cicd
- observability

Modules must remain reusable and should not contain unnecessary development-specific configuration.

Keep resources within the module that owns their architectural responsibility.

Use module outputs and input variables to pass required values between modules.

Avoid circular module dependencies.

Follow the dependency direction established in `architecture.md`.

Do not move resources between modules without a clear architectural reason and consideration of Terraform state impact.

---

## No Hardcoding

Do not hardcode:

- AWS account IDs
- ARNs
- VPC IDs
- subnet IDs
- route table IDs
- security group IDs
- ECR URLs
- CloudFront distribution IDs
- hosted zone IDs
- generated AWS resource identifiers

Use:

- Terraform variables
- locals
- resource references
- data sources
- module outputs

Static architectural configuration values may be used when intentional and not generated account-specific identifiers.

---

## Variables

Variables should:

- have meaningful names
- declare explicit types
- include useful descriptions
- include validation where appropriate

Development-specific values belong primarily in:

`envs/dev/terraform.tfvars`

Do not put secrets in committed `terraform.tfvars`.

Use appropriate secret-management mechanisms for sensitive values.

Mark sensitive Terraform variables as `sensitive = true` where appropriate.

---

## Outputs

Modules should expose only values required by another module, the root module, CI/CD, or operators.

Do not create outputs merely because a resource has an ID or ARN.

Examples, when required by downstream consumers:

- `vpc_id`
- `public_subnet_ids`
- `private_subnet_ids`
- `alb_arn`
- `alb_dns_name`
- `ecr_repository_url`
- `ecs_cluster_name`
- `ecs_service_name`
- `dynamodb_table_name`
- `dynamodb_table_arn`
- `cloudfront_distribution_id`
- `cloudfront_domain_name`
- `frontend_bucket_name`

Do not expose secret values through Terraform outputs unless explicitly required and appropriately marked sensitive.

---

## Naming

Use locals for derived names.

Preferred pattern:

```hcl id="d3azuh"
locals {
  name_prefix = "${var.app_name}-${var.environment}"
}
```

Derive resource names from `local.name_prefix` where appropriate.

Avoid repeating naming logic across resources.

Respect AWS service-specific naming restrictions.

---

## Tags

Use common tags where AWS resources support them.

Recommended:

- `Project`
- `Environment`
- `ManagedBy`
- `Owner`

Pass common tags from the root environment to reusable modules where practical.

Merge common tags with resource-specific tags rather than duplicating tag definitions throughout the configuration.

---

## State

The bootstrap configuration creates the remote-state infrastructure.

Bootstrap uses separate state from the main development environment.

Development state key:

`dev/terraform.tfstate`

Treat Terraform state as critical infrastructure data.

Never commit:

- `*.tfstate`
- `*.tfstate.*`
- `.terraform/`
- saved Terraform plan files

Do not manually edit Terraform state files.

Do not delete or recreate Terraform-managed resources solely to resolve configuration issues without first considering Terraform state impact.

---

## Backend

The environment backend configuration belongs under:

`envs/dev/`

Do not attempt to create the backend S3 bucket from the same Terraform state that depends on that backend.

Bootstrap the remote-state infrastructure separately before initializing the main DEV root.

Do not place a `backend` block inside reusable child modules.

---

## Providers

Configure AWS providers in the root environment:

`envs/dev/providers.tf`

Provider aliases should also be defined there.

Examples:

- default AWS provider/region
- `aws.us_east_1` when required for CloudFront custom-domain ACM certificates

Child modules should inherit the default provider configuration or receive provider aliases explicitly when required.

Do not define unnecessary provider blocks inside reusable child modules.

Do not place AWS credentials inside provider configuration.

Use the established AWS authentication mechanism outside Terraform configuration.

For the current DEV CloudFront default-domain configuration, a custom ACM certificate is not required. The `aws.us_east_1` alias may remain available for future custom-domain requirements without creating ACM resources now.

---

## Module Dependency Direction

Follow the architecture defined in `architecture.md`.

For the current application path, preserve the dependency direction:

```text id="h5ct45"
network/data → backend → edge
```

Backend owns the internal ALB and ECS resources.

Backend exposes the required ALB interface values:

- `alb_arn`
- `alb_dns_name`

Edge consumes those outputs and owns the CloudFront VPC Origin.

Backend must not depend on edge.

Do not introduce circular module dependencies.

---

## Terraform Workflow

Before committing:

```bash id="j05ufr"
terraform fmt -recursive
```

CI/CD may verify formatting using:

```bash id="vprsyk"
terraform fmt -check -recursive
```

Before planning or applying infrastructure:

```bash id="3g9d7r"
terraform init
terraform validate
terraform plan
```

Review the plan before:

```bash id="k6ox2x"
terraform apply
```

A successful `terraform plan` does not automatically authorize `terraform apply`.

Do not run `terraform apply` when a specification or implementation task explicitly stops at validation or planning.

Investigate unexpected changes, replacements, or destroys before applying.

---

## Plan Review

Before applying infrastructure changes, review the Terraform plan for:

- unexpected resource destruction
- unexpected resource replacement
- unintended public resources
- security group changes
- IAM permission changes
- state inconsistencies
- duplicate resources
- unexpected recurring-cost resources
- hardcoded identifiers
- resources outside the current DEV scope

For clean-slate work where no infrastructure exists in the active state, the expected plan should normally contain resources to add with no unexpected changes or destroys.

Do not force a plan to match an expected count without investigating differences.

---

## Clean-Slate Refactoring

The current modular architecture is a clean-slate implementation.

Previous application infrastructure was intentionally removed, and legacy Terraform files may remain in the repository temporarily for reference.

Do not create `moved` blocks or perform Terraform state migration for legacy application resources unless explicitly requested.

The current Terraform source of truth is:

- `ecs-terraform/modules/`
- `ecs-terraform/envs/dev/`

Legacy Terraform files outside these locations are reference-only.

Do not modify, import, migrate, or use legacy Terraform resources as the implementation source unless explicitly requested.

Before deployment, verify that the active remote state does not contain stale records for previously deleted application resources.

If stale state is discovered, stop and review the state before changing, removing, importing, or recreating resources.

---

## Environment Independence

Reusable modules should not assume DEV-specific values unless those values are intentionally provided through variables.

Environment-specific configuration should normally be supplied by:

- root module variables
- environment `terraform.tfvars`
- provider configuration
- module inputs

Future staging and production environments may use different:

- resource sizing
- domains
- certificates
- scaling settings
- backup policies
- security controls
- monitoring
- retention periods
- availability requirements

Do not assume DEV defaults automatically apply to future environments.

---

## Change Discipline

Make the smallest Terraform change required to satisfy the approved requirement.

Do not modify unrelated modules or resources.

Do not introduce speculative infrastructure.

Do not add AWS services merely to increase architectural complexity.

When implementing an approved specification, follow:

1. `requirements.md`
2. `design.md`
3. `tasks.md`
4. project steering files

If these documents conflict, identify and resolve the conflict before making a significant, destructive, or state-affecting infrastructure change.

---

## Cost Awareness

Prefer cost-conscious infrastructure for DEV.

Do not create unnecessary:

- NAT Gateways
- VPC