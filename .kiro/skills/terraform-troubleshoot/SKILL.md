---
name: terraform-troubleshoot
description: Diagnose Terraform, AWS provider, remote state, backend, module, and dependency problems in the Erudition Solution development environment.
---

# Terraform Troubleshooting Skill

## Purpose

Diagnose Terraform problems methodically without creating unnecessary
infrastructure changes.

Current environment:

`ecs-terraform/envs/dev`

## First Rule

Do not immediately:

- delete Terraform state
- delete the S3 state bucket
- destroy infrastructure
- remove `.terraform`
- run `terraform destroy`
- recreate AWS resources manually

Understand the error first.

## Troubleshooting Process

1. Read the complete error.
2. Identify the Terraform working directory.
3. Identify the resource/module involved.
4. Determine whether the problem is:
   - syntax
   - provider
   - backend
   - state
   - dependency
   - AWS permissions
   - AWS API
   - networking
   - configuration
5. Inspect the relevant Terraform files.
6. Check Terraform state when necessary.
7. Make the smallest safe correction.
8. Run validation.
9. Run plan.
10. Review the plan before applying.

## Backend Problems

The development environment uses remote state.

Expected state key:

`dev/terraform.tfstate`

The bootstrap configuration creates the backend infrastructure.

If Terraform reports that the backend bucket does not exist:

- verify bootstrap infrastructure
- verify backend configuration
- verify AWS profile/account
- verify AWS region

Do not create a second random backend bucket to bypass the problem.

## State Problems

Useful commands may include:

`terraform state list`

`terraform state show`

`terraform state mv`

Use state modification commands carefully.

Prefer Terraform `moved` blocks for code-based refactoring when appropriate.

Never modify Terraform state blindly.

## Module Refactoring

When an existing resource moves from:

`aws_resource.example`

to:

`module.example.aws_resource.example`

Terraform may interpret this as:

destroy old resource
create new resource

Preserve the state relationship before applying.

## Provider Problems

Check:

- Terraform version
- AWS provider version
- provider aliases
- region
- AWS profile
- module provider mapping

Provider configuration belongs primarily in:

`envs/dev/providers.tf`

## AWS Authentication

When authentication fails, verify the active identity.

Use AWS CLI identity checks when appropriate.

Do not print or expose secret access keys.

Never request that AWS secret keys be committed to source control.

## Dependency Problems

Prefer Terraform references over manual `depends_on`.

Use `depends_on` only when Terraform cannot infer the dependency naturally.

Avoid circular module dependencies.

## Lock Problems

If Terraform reports a state lock:

- determine whether another Terraform operation is running
- identify whether the lock is stale
- do not force-unlock an active operation

Use force unlock only after confirming that no legitimate Terraform
process owns the lock.

## Resource Already Exists

Do not automatically delete an existing AWS resource.

Determine whether:

- Terraform already manages it
- it belongs to another state
- it needs importing
- naming conflicts exist

## Troubleshooting Goal

The objective is not merely to remove the error.

The objective is to restore Terraform to a predictable state where:

`terraform validate`

succeeds and:

`terraform plan`

shows the intended infrastructure changes only.