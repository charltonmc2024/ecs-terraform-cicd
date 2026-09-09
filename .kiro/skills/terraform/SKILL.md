# Terraform Skill

## Purpose

Use this skill when creating, modifying, reviewing, validating, debugging, or planning Terraform infrastructure for the Online Tutoring Platform.

This skill defines the **workflow for Terraform tasks**.

Project architecture and standards are defined by the project's Steering files:

* `project-overview.md`
* `aws-architecture.md`
* `terraform-standards.md`

These Steering files take precedence over assumptions made in this skill.

---

# 1. When to Use This Skill

Use this skill when the task involves:

* Creating Terraform resources
* Modifying Terraform resources
* Debugging Terraform errors
* Reviewing Terraform configuration
* Creating Terraform modules
* Changing AWS infrastructure
* Adding AWS services
* Changing networking
* Changing IAM
* Changing ECS
* Changing ECR
* Changing S3
* Changing CloudFront
* Changing ACM
* Changing Route 53
* Changing DynamoDB
* Running Terraform validation
* Preparing Terraform plans
* Reviewing infrastructure changes

Do not use this skill for application-only changes that do not affect Terraform infrastructure.

---

# 2. Required Project Context

Before making Terraform changes, understand the current project architecture.

The target architecture is:

```text
Users
  │
  ▼
Route 53
  │
  ▼
CloudFront
  │
  ├── S3
  │    └── React Frontend
  │
  └── ALB
       │
       ▼
   ECS Fargate
       │
       └── Python API
              │
              ▼
          DynamoDB

ECR
 │
 └── Python Backend Image
       │
       ▼
   ECS Fargate
```

Terraform manages the AWS infrastructure supporting this architecture.

---

# 3. Before Changing Terraform

Always inspect the existing Terraform configuration first.

Do not immediately create new resources.

Check:

1. Existing Terraform files
2. Existing resources
3. Existing variables
4. Existing locals
5. Existing outputs
6. Existing providers
7. Existing modules
8. Existing IAM roles
9. Existing security groups
10. Existing dependencies

Determine whether the requested resource already exists.

If it exists, modify the existing resource instead of creating a duplicate.

---

# 4. Check the Steering Files

Before making architectural changes, check:

```text
project-overview.md
aws-architecture.md
terraform-standards.md
```

Use them to determine:

* Required AWS services
* Naming conventions
* Networking requirements
* Security requirements
* Terraform version
* Provider requirements
* Environment strategy
* Cost requirements

Do not contradict the Steering files without a clear reason.

If the requested change conflicts with the architecture, identify the conflict before implementing it.

---

# 5. Terraform Workflow

Use this workflow:

```text
Understand Request
       │
       ▼
Inspect Existing Terraform
       │
       ▼
Check Steering Files
       │
       ▼
Identify Resources Affected
       │
       ▼
Make Smallest Required Change
       │
       ▼
terraform fmt
       │
       ▼
terraform init
       │
       ▼
terraform validate
       │
       ▼
terraform plan
       │
       ▼
Review Plan
       │
       ▼
Apply Only When Appropriate
       │
       ▼
Verify Resources
```

Do not skip directly from editing Terraform to `terraform apply`.

---

# 6. Inspect Before Creating

Before creating a resource, search the existing configuration.

For example, before creating an ECS cluster:

```text
Search existing files for:
aws_ecs_cluster
```

Before creating an IAM role:

```text
Search existing files for:
aws_iam_role
```

Before creating a DynamoDB table:

```text
Search existing files for:
aws_dynamodb_table
```

Before creating an S3 bucket:

```text
Search existing files for:
aws_s3_bucket
```

Avoid duplicate Terraform resource declarations.

---

# 7. Resource Naming

Follow the project's naming convention.

Preferred pattern:

```text
<project>-<environment>-<resource>
```

Example:

```text
tutoring-dev-vpc
tutoring-dev-alb
tutoring-dev-ecs
tutoring-dev-ecr
tutoring-dev-dynamodb
```

Use Terraform locals when appropriate.

Example:

```hcl
locals {
  name_prefix = "${var.project_name}-${var.environment}"
}
```

Then:

```hcl
name = "${local.name_prefix}-ecs"
```

---

# 8. Variables

Do not hard-code environment-specific configuration.

Use variables for values such as:

* AWS region
* Environment
* Project name
* VPC CIDR
* Subnet CIDRs
* ECS CPU
* ECS memory
* Desired task count
* Domain name
* Container port
* DynamoDB configuration

Example:

```hcl
variable "aws_region" {
  description = "AWS region for the application"
  type        = string
}
```

Prefer variables over repeated hard-coded values.

---

# 9. Locals

Use locals for values reused throughout the configuration.

Example:

```hcl
locals {
  name_prefix = "${var.project_name}-${var.environment}"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}
```

Avoid creating locals for values that are used only once.

---

# 10. AWS Provider

Keep provider configuration centralized.

Example:

```hcl
provider "aws" {
  region = var.aws_region
}
```

Use provider aliases when resources must exist in different AWS regions.

ACM for CloudFront is the primary example.

```hcl
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}
```

---

# 11. ACM Workflow

Pay special attention to ACM.

The CloudFront certificate must use the `us-east-1` provider:

```hcl
resource "aws_acm_certificate" "cloudfront" {
  provider          = aws.us_east_1
  domain_name       = var.domain_name
  validation_method = "DNS"
}
```

The ALB certificate must use the provider for the same region as the ALB.

Do not accidentally use the CloudFront certificate for an ALB in another region.

---

# 12. Networking Workflow

When modifying networking:

1. Inspect the existing VPC.
2. Inspect existing subnets.
3. Check CIDR ranges.
4. Check route tables.
5. Check Internet Gateway.
6. Check NAT Gateway.
7. Check Availability Zones.
8. Check security groups.
9. Check dependencies.

Before adding a subnet, verify that its CIDR does not overlap another subnet.

Example:

```text
VPC
10.0.0.0/16

Public-A
10.0.1.0/24

Public-B
10.0.2.0/24

Private-A
10.0.3.0/24

Private-B
10.0.4.0/24
```

Do not introduce overlapping CIDRs.

---

# 13. ECS Workflow

When modifying ECS:

```text
ECR
 │
 ▼
ECS Task Definition
 │
 ▼
ECS Service
 │
 ▼
Target Group
 │
 ▼
ALB
```

Check all related resources before modifying one of them.

For ECS changes, inspect:

* Cluster
* Task definition
* Container definition
* CPU
* Memory
* Container port
* IAM task execution role
* IAM task role
* Security group
* Subnets
* Target group
* ALB listener
* Health check
* Desired task count
* ECR image

Do not modify ECS in isolation when the change affects connected resources.

---

# 14. ECR Workflow

When working with ECR:

```text
Python Source
      │
      ▼
Docker Build
      │
      ▼
ECR
      │
      ▼
ECS
```

Use versioned image tags where possible.

Prefer:

```text
commit-abc123
v1.0.0
build-123
```

Avoid relying exclusively on:

```text
latest
```

Terraform should manage the ECR repository.

Application image builds and pushes should normally be handled by CI/CD rather than Terraform.

---

# 15. S3 Workflow

The React frontend is hosted in S3.

When modifying S3:

* Keep the bucket private.
* Enable appropriate encryption.
* Block public access.
* Use CloudFront as the public frontend entry point.
* Use an appropriate CloudFront-to-S3 access mechanism.
* Avoid public bucket policies.

Preferred:

```text
User
 │
 ▼
CloudFront
 │
 ▼
Private S3 Bucket
 │
 ▼
React
```

Do not make the bucket public merely to resolve a CloudFront or frontend issue.

---

# 16. CloudFront Workflow

When modifying CloudFront:

Check:

* Distribution
* S3 origin
* ALB/API origin
* Cache behaviors
* `/api/*` behavior
* Default behavior
* HTTPS settings
* ACM certificate
* Custom domain
* Origin access configuration

Target routing:

```text
/*       → S3
/api/*   → ALB
```

Maintain HTTPS.

---

# 17. ALB Workflow

When modifying the ALB:

Check:

```text
ALB
 │
 ├── Security Group
 │
 ├── Listener
 │
 ├── ACM Certificate
 │
 └── Target Group
        │
        ▼
       ECS
```

Verify:

* Listener protocol
* Listener port
* Certificate
* Target group
* Target port
* Health check
* Security groups
* ECS service attachment

Do not expose ECS tasks directly to the internet when the architecture calls for ALB-based access.

---

# 18. DynamoDB Workflow

When modifying DynamoDB:

First determine the application's access patterns.

Consider:

* Partition key
* Sort key
* Query patterns
* Required indexes
* Read/write behavior
* Billing mode
* Encryption
* Point-in-time recovery
* Data protection

Do not redesign the DynamoDB data model simply because a relational database pattern appears more familiar.

The frontend must not directly access DynamoDB.

Preferred:

```text
React
 │
 ▼
CloudFront
 │
 ▼
ALB
 │
 ▼
Python API
 │
 ▼
DynamoDB
```

---

# 19. IAM Workflow

When modifying IAM:

1. Identify which AWS service needs access.
2. Identify the exact AWS actions required.
3. Identify the exact resources required.
4. Grant the minimum permissions.
5. Avoid wildcard resources where practical.
6. Avoid broad administrative policies.
7. Check whether an existing role should be modified rather than creating a new role.

Example:

```text
ECS Task Role
      │
      └── DynamoDB permissions
```

Do not give the ECS application permissions unrelated to its function.

---

# 20. Security Group Workflow

Security groups should represent application communication paths.

Preferred:

```text
Internet
   │
   ▼
ALB Security Group
   │
   ▼
ECS Security Group
```

ECS inbound traffic should come from the ALB security group.

Avoid unrestricted inbound rules such as:

```hcl
cidr_blocks = ["0.0.0.0/0"]
```

unless the rule is specifically required.

---

# 21. Terraform State

Never commit Terraform state.

Do not modify state files manually.

Never commit:

```text
terraform.tfstate
terraform.tfstate.backup
```

When an existing AWS resource needs to become Terraform-managed, use Terraform's appropriate import functionality.

Do not recreate an existing production resource simply because it is not currently represented in Terraform.

---

# 22. Terraform Formatting

After modifying Terraform:

```bash
terraform fmt
```

For CI validation:

```bash
terraform fmt -check
```

Terraform code should remain consistently formatted.

---

# 23. Terraform Initialization

When required:

```bash
terraform init
```

Use initialization after:

* Adding providers
* Changing backend configuration
* Adding modules
* Changing provider requirements

Do not repeatedly run initialization unnecessarily.

---

# 24. Terraform Validation

Always run:

```bash
terraform validate
```

after Terraform configuration changes.

Validation should occur before planning or applying.

Expected workflow:

```text
terraform fmt
terraform validate
terraform plan
```

---

# 25. Terraform Plan

Always inspect the plan before applying infrastructure changes.

Run:

```bash
terraform plan
```

Pay special attention to:

```text
Plan: X to add, Y to change, Z to destroy
```

Investigate unexpected:

```text
destroy
replace
```

operations.

Be especially careful with:

* DynamoDB
* S3
* VPC
* ECS
* ALB
* CloudFront
* Route 53
* ACM
* IAM

---

# 26. Destructive Changes

Do not intentionally destroy infrastructure unless:

* The user explicitly requested it, or
* The requested architecture requires it.

If Terraform proposes unexpected destruction or replacement:

1. Stop.
2. Identify the cause.
3. Inspect dependencies.
4. Check resource configuration.
5. Determine whether state drift exists.
6. Explain the impact.
7. Fix the configuration if appropriate.

Never silently accept unexpected destructive changes.

---

# 27. Apply Workflow

Only apply after reviewing the plan.

Normal workflow:

```bash
terraform plan
```

Review.

Then:

```bash
terraform apply
```

For a previously saved plan:

```bash
terraform plan -out=tfplan
terraform apply tfplan
```

Do not use:

```bash
terraform apply -auto-approve
```

for significant infrastructure changes unless automated deployment explicitly requires it.

---

# 28. Debugging Workflow

When Terraform fails:

```text
Terraform Error
      │
      ▼
Identify Resource
      │
      ▼
Read Full Error
      │
      ▼
Inspect Terraform Configuration
      │
      ▼
Inspect Dependencies
      │
      ▼
Check AWS Resource State
      │
      ▼
Identify Root Cause
      │
      ▼
Make Smallest Fix
      │
      ▼
terraform fmt
      │
      ▼
terraform validate
      │
      ▼
terraform plan
```

Do not blindly change multiple resources at once.

---

# 29. Common Error Investigation

## InvalidSubnet.Conflict

Check:

* VPC CIDR
* Existing subnet CIDRs
* New subnet CIDR
* Availability Zone
* Terraform state

Do not simply choose another CIDR without understanding the existing network layout.

---

## Duplicate Resource

Example:

```text
Duplicate resource "aws_iam_role"
```

Search the entire Terraform project for the resource declaration.

Remove or consolidate the duplicate rather than renaming resources arbitrarily.

---

## Unsupported Block

If Terraform reports:

```text
Unsupported block type
```

Check:

* Terraform syntax
* Resource documentation
* Provider version
* Resource type
* Block nesting

Do not assume the block belongs to the resource simply because it appears conceptually related.

---

## Reference Error

Example:

```text
Reference to undeclared resource
```

Check:

1. Resource name
2. Resource type
3. File location
4. Whether the resource was renamed
5. Whether the resource was removed

Do not create a duplicate resource merely to satisfy a broken reference.

---

# 30. Dependencies

Prefer implicit dependencies.

Example:

```hcl
target_group_arn = aws_lb_target_group.app.arn
```

Use `depends_on` only when Terraform cannot determine the dependency automatically.

Avoid unnecessary dependency declarations.

---

# 31. Modules

Use modules when they provide meaningful:

* Reuse
* Separation
* Maintainability
* Environment consistency

Do not create a module for every individual resource.

Avoid unnecessary abstraction for the MVP.

Prefer simple Terraform that is easy to understand and debug.

---

# 32. Outputs

Create outputs for useful infrastructure information.

Examples:

```hcl
output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.frontend.domain_name
}
```

```hcl
output "ecr_repository_url" {
  value = aws_ecr_repository.backend.repository_url
}
```

```hcl
output "alb_dns_name" {
  value = aws_lb.app.dns_name
}
```

Never expose secrets through Terraform outputs.

---

# 33. CI/CD Validation

Terraform changes should be validated in CI/CD.

Recommended sequence:

```text
Code Commit
    │
    ▼
Terraform Format Check
    │
    ▼
Terraform Init
    │
    ▼
Terraform Validate
    │
    ▼
Terraform Plan
    │
    ▼
Review / Approval
    │
    ▼
Terraform Apply
```

Infrastructure deployment should be separated from application deployment when practical.

---

# 34. Application vs Infrastructure

Keep responsibilities separated.

Terraform manages:

```text
VPC
S3
CloudFront
ACM
Route 53
ALB
ECS
ECR
DynamoDB
IAM
Security Groups
```

CI/CD manages:

```text
React Build
React Deployment
Docker Build
Docker Push
ECS Application Deployment
```

Terraform should not be used as the normal mechanism for building and pushing every application Docker image.

---

# 35. Cost-Conscious Development

The project is initially an MVP.

Before adding infrastructure, consider:

```text
Does this resource solve an actual requirement?
```

Prefer the smallest architecture that satisfies:

* Security
* Functionality
* Reliability
* Maintainability

For development, consider:

* Small ECS task sizes
* Low desired task count
* DynamoDB on-demand billing
* Single NAT Gateway when appropriate
* Minimal unnecessary infrastructure

Do not sacrifice required production security or availability merely to reduce cost.

---

# 36. Change Scope

When fixing a problem, make the smallest change that solves the problem.

Avoid unrelated refactoring.

For example:

If the task is:

```text
Fix ECS health check
```

Do not simultaneously:

* Redesign the VPC
* Replace the ALB
* Redesign DynamoDB
* Change IAM architecture
* Rename every resource

Keep changes focused.

---

# 37. Verification

After applying infrastructure changes, verify the affected resources.

Examples:

### S3

Verify:

```text
Bucket exists
Public access blocked
CloudFront access works
React files available
```

### CloudFront

Verify:

```text
Distribution deployed
HTTPS works
Custom domain works
S3 origin works
/api/* routes correctly
```

### ALB

Verify:

```text
Listener works
Certificate works
Target group healthy
ECS targets registered
```

### ECS

Verify:

```text
Tasks running
Container healthy
Logs available
ECR image pulled
```

### DynamoDB

Verify:

```text
Table exists
Correct keys
Backend can access table
IAM permissions work
```

---

# 38. Documentation

When an infrastructure change alters the architecture, update the appropriate Steering/documentation file.

Update:

```text
project-overview.md
```

when the overall project architecture changes.

Update:

```text
aws-architecture.md
```

when AWS architecture changes.

Update:

```text
terraform-standards.md
```

when Terraform conventions change.

Do not duplicate detailed architecture information unnecessarily across multiple files.

---

# 39. Agent Behavior

When using this skill, the agent should:

* Inspect before modifying.
* Reuse existing resources.
* Avoid duplicates.
* Follow project naming conventions.
* Follow least privilege.
* Preserve security boundaries.
* Prefer private ECS tasks.
* Keep S3 private.
* Use ACM for HTTPS.
* Remember the CloudFront certificate region requirement.
* Keep DynamoDB behind the backend.
* Avoid unnecessary AWS services.
* Minimize infrastructure changes.
* Validate Terraform after changes.
* Review Terraform plans.
* Stop when unexpected destruction is detected.
* Explain important infrastructure risks.
* Verify changes after deployment.

---

# 40. Definition of Done

A Terraform change is complete when:

```text
☑ Existing configuration inspected
☑ Steering files checked
☑ Required resources identified
☑ No duplicate resources introduced
☑ Terraform formatted
☑ Terraform initialized when required
☑ Terraform validated
☑ Terraform plan reviewed
☑ Unexpected destruction investigated
☑ Infrastructure applied when appropriate
☑ AWS resources verified
☑ Documentation updated if architecture changed
```

---

# 41. Core Terraform Workflow

Always prefer:

```text
             ┌────────────────────┐
             │ Understand Request │
             └─────────┬──────────┘
                       ▼
             ┌────────────────────┐
             │ Inspect Existing   │
             │ Terraform          │
             └─────────┬──────────┘
                       ▼
             ┌────────────────────┐
             │ Check Steering     │
             │ Files              │
             └─────────┬──────────┘
                       ▼
             ┌────────────────────┐
             │ Make Smallest      │
             │ Required Change    │
             └─────────┬──────────┘
                       ▼
             ┌────────────────────┐
             │ terraform fmt      │
             └─────────┬──────────┘
                       ▼
             ┌────────────────────┐
             │ terraform validate │
             └─────────┬──────────┘
                       ▼
             ┌────────────────────┐
             │ terraform plan     │
             └─────────┬──────────┘
                       ▼
             ┌────────────────────┐
             │ Review Changes     │
             └─────────┬──────────┘
                       ▼
             ┌────────────────────┐
             │ terraform apply    │
             └─────────┬──────────┘
                       ▼
             ┌────────────────────┐
             │ Verify AWS         │
             │ Resources          │
             └────────────────────┘
```

## Core Rule

**Inspect → Understand → Modify → Format → Validate → Plan → Review → Apply → Verify**

Never skip the inspection and plan stages for significant infrastructure changes.
