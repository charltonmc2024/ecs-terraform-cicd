---
name: terraform-validate
description: Validate and review Terraform changes for the Erudition Solution development environment before deployment.
---

# Terraform Validation Skill

## Purpose

Validate Terraform configuration before infrastructure is deployed.

Current deployment root:

`ecs-terraform/envs/dev`

Do not validate or create staging or production environments unless
explicitly requested.

## Validation Workflow

Run validation in this order:

1. Terraform formatting
2. Terraform initialization
3. Terraform validation
4. Terraform plan
5. Plan review

## Formatting

From the Terraform project:

`terraform fmt -recursive`

For CI:

`terraform fmt -check -recursive`

Formatting failures should be corrected before deployment.

## Initialization

Run from:

`ecs-terraform/envs/dev`

Use:

`terraform init`

Use `-reconfigure` only when backend configuration intentionally changed.

Do not casually delete:

- `.terraform`
- state files
- backend infrastructure

to solve initialization problems.

## Validation

Run:

`terraform validate`

Do not proceed if validation fails.

Investigate:

- invalid references
- missing variables
- provider configuration
- module paths
- unsupported arguments
- incorrect types
- dependency problems

## Planning

Run:

`terraform plan`

Use the appropriate development variable configuration.

Review the entire plan before applying.

## Plan Review

Explicitly inspect:

- resources being created
- resources being modified
- resources being destroyed
- replacements
- IAM changes
- networking changes
- security group changes
- public exposure
- database changes

## Refactoring Safety

When Terraform resources have been moved into modules, pay particular
attention to plans showing:

destroy

followed by:

create

for what should be the same AWS resource.

This may indicate that Terraform state addresses were not migrated.

Use `moved` blocks where appropriate.

## Security Review

Flag plans that introduce:

- `0.0.0.0/0` unexpectedly
- public ECS tasks
- public S3 buckets
- excessive IAM permissions
- unencrypted sensitive resources
- hardcoded credentials
- exposed secrets

## Cost Review

Flag potentially significant development costs such as:

- multiple NAT Gateways
- unnecessary interface endpoints
- oversized ECS tasks
- excessive log retention
- unnecessary load balancers
- unnecessary managed services

## Apply

Do not treat a successful plan as automatic approval to apply.

The expected workflow is:

fmt
 |
init
 |
validate
 |
plan
 |
review
 |
apply

Only apply after the plan is understood.