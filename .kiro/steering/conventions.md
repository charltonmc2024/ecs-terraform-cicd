# Project Conventions

## Current Scope

Focus on completing:

`envs/dev`

Do not create staging or production infrastructure unless explicitly requested.

Design reusable modules so they can support future environments without introducing staging or production resources now.

---

## Terraform Naming

Use:

`snake_case`

for Terraform:

- resources
- variables
- locals
- outputs
- data sources
- module names

Use meaningful and descriptive names.

Avoid names such as:

- `resource1`
- `test123`
- `thing`
- `temp`

Resource labels should describe their purpose rather than their implementation order.

---

## AWS Naming

Use a consistent resource naming pattern.

Preferred concept:

`${app_name}-${environment}-${resource}`

Example:

`eruditiontx-dev-ecs-service`

Use locals rather than repeating naming logic.

Prefer a shared naming prefix such as:

```hcl
locals {
  name_prefix = "${var.app_name}-${var.environment}"
}
```

Then derive resource names from `local.name_prefix`.

Do not hardcode environment-specific names when they can be derived from variables or locals.

Respect AWS service-specific naming restrictions when applying the naming convention.

---

## Hardcoded Values

Do not hardcode account-specific or environment-specific AWS identifiers when they can be obtained from Terraform references, variables, data sources, or module outputs.

Avoid hardcoding:

- AWS account IDs
- ARNs
- VPC IDs
- subnet IDs
- security group IDs
- route table IDs
- ECR repository URLs
- CloudFront distribution IDs
- hosted zone IDs
- generated AWS resource identifiers

Prefer Terraform resource references and module outputs.

Static configuration values may be used when they are intentional architectural settings rather than generated AWS identifiers.

---

## Terraform Files

Use descriptive filenames.

Examples:

- `main.tf`
- `variables.tf`
- `outputs.tf`
- `nat.tf`
- `endpoints.tf`
- `security-groups.tf`
- `ecs.tf`
- `alb.tf`
- `iam.tf`
- `cloudfront.tf`
- `s3.tf`
- `logs.tf`
- `autoscaling.tf`

Terraform loads all `.tf` files in the same directory as one module.

File separation exists primarily for readability and maintainability.

Do not create unnecessary files merely to separate very small configuration blocks.

Follow the established file structure of an existing module when extending that module.

---

## Module Boundaries

Keep resources inside the module that owns their architectural responsibility.

Use module outputs to pass required values between modules.

Avoid reaching across module boundaries to reference resources that should instead be exposed through outputs.

Preserve the dependency direction defined in `architecture.md`.

Avoid circular module dependencies.

Do not move resources between modules without a clear architectural reason and review of Terraform state impact.

---

## Comments

Comments should explain why something exists or clarify a non-obvious architectural decision.

Good:

```hcl
# Internal ALB is accessed through CloudFront VPC Origin.
```

Avoid comments that merely repeat Terraform syntax.

Prefer clear Terraform names over excessive comments.

---

## Git

Never commit:

- `.terraform/`
- `*.tfstate`
- `*.tfstate.*`
- saved Terraform plan files
- credentials
- private keys
- secrets
- local files containing secrets

Commit the Terraform dependency lock file for deployable root modules when appropriate.

Before committing, review:

```bash
git status
git diff
```

Do not commit generated or temporary files unless they are intentionally part of the repository.

---

## Terraform Validation

Before committing Terraform changes, format the configuration:

```bash
terraform fmt -recursive
```

Verify formatting when required by CI/CD:

```bash
terraform fmt -check -recursive
```

Validate the active development root:

```bash
terraform validate
```

Before infrastructure changes, run:

```bash
terraform plan
```

Review the plan before applying.

Do not treat a successful `terraform plan` as authorization to run `terraform apply`.

Resolve unexpected resource replacement, deletion, or modification before applying infrastructure changes.

---

## Terraform State

Treat Terraform state as critical infrastructure data.

Use the configured remote backend for deployable environments.

Do not manually edit Terraform state files.

Do not delete, recreate, move, or rename Terraform-managed resources solely to resolve configuration problems without first considering state impact.

Do not introduce `moved` blocks or state-migration operations unless an actual resource migration requires them.

---

## Cost

Prefer cost-conscious development resources.

Do not create:

- unnecessary NAT Gateways
- oversized compute
- excessive log retention
- unnecessary VPC endpoints
- duplicate CI/CD systems
- unnecessary managed services
- duplicate infrastructure
- speculative resources for future environments

when a simpler secure solution satisfies the requirement.

Cost optimization must not introduce unnecessary public exposure or weaken required security controls.

---

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

Prefer extending the established architecture over replacing it when the existing design can satisfy the requirement.

---

## Environment Design

Reusable modules should support future environment-specific configuration where practical.

Current implementation remains limited to:

`envs/dev`

Do not create:

- `envs/staging`
- `envs/prod`
- staging resources
- production resources
- staging pipeline stages
- production pipeline stages

unless explicitly requested.

Future staging and production environments may use different sizing, security controls, domains, certificates, monitoring, availability, backup, and deployment policies.

Do not assume DEV-specific cost optimizations automatically apply to staging or production.

---

## Development Priority

Finish the development environment end-to-end before expanding the project to additional environments.

Current implementation priority:

1. Network
2. Data
3. Backend
4. Edge
5. Jenkins CI/CD
6. Observability

When a module is complete, avoid modifying it unless:

- a downstream dependency requires an interface change
- validation identifies a defect
- security requires a correction
- the approved architecture changes

Complete and validate each phase before moving to the next whenever practical.

---

## Change Discipline

Make the smallest change necessary to satisfy the approved requirement.

Do not modify unrelated files, modules, resources, or architecture.

Do not add speculative features.

Do not implement future requirements unless explicitly requested.

When working from approved specifications, keep implementation consistent with:

1. `requirements.md`
2. `design.md`
3. `tasks.md`
4. project steering files

If these documents conflict, identify the conflict before making a significant or destructive infrastructure change.