# Terraform Standards

## 1. Purpose

This document defines the Terraform standards and conventions for the Online Tutoring Platform.

Terraform is the required Infrastructure as Code (IaC) tool for provisioning and managing AWS infrastructure.

All AWS infrastructure changes should be implemented through Terraform rather than manually through the AWS Management Console whenever practical.

---

## 2. AWS Architecture

The Terraform configuration manages the following primary AWS services:

```text
Route 53
    │
    ▼
CloudFront
    │
    ├── S3
    │     └── React Frontend
    │
    └── ALB
          │
          ▼
       ECS Fargate
          │
          ▼
       DynamoDB


ACM
├── CloudFront Certificate
└── ALB Certificate

ECR
└── Backend Docker Image
```

The application architecture is:

* **React** — frontend
* **Python** — backend/API
* **Amazon S3** — React frontend hosting
* **Amazon CloudFront** — CDN
* **AWS Certificate Manager (ACM)** — TLS certificates
* **Route 53** — DNS
* **Application Load Balancer** — backend traffic
* **ECS Fargate** — Python backend
* **ECR** — backend Docker images
* **DynamoDB** — application data

> If the application implementation differs from this architecture, update this document before changing the Terraform design.

---

## 3. Terraform Version

Use a consistent Terraform version across:

* Local development
* VS Code
* CI/CD
* CodeBuild
* Development environments

The Terraform version should be declared in `terraform.tf`.

Example:

```hcl
terraform {
  required_version = "~> 1.16.0"
}
```

Do not allow different environments to silently use incompatible Terraform versions.

---

## 4. AWS Provider

Pin the AWS provider to a compatible version range.

Example:

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
```

Provider configuration should be centralized.

Example:

```hcl
provider "aws" {
  region = var.aws_region
}
```

Do not hard-code AWS regions throughout individual resource definitions.

---

## 5. Provider Aliases

Use provider aliases when resources must exist in different AWS regions.

This is particularly important for ACM.

CloudFront requires its ACM certificate to exist in `us-east-1`.

Example:

```hcl
provider "aws" {
  region = var.aws_region
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}
```

The CloudFront ACM certificate should use:

```hcl
provider = aws.us_east_1
```

The ALB ACM certificate should use the provider for the same region as the ALB.

---

## 6. Project Structure

Use a clear separation between infrastructure components.

Recommended structure:

```text
terraform/
│
├── terraform.tf
├── provider.tf
├── variables.tf
├── outputs.tf
├── locals.tf
│
├── vpc.tf
├── subnets.tf
├── nat.tf
│
├── security-groups.tf
│
├── s3.tf
├── cloudfront.tf
│
├── acm.tf
├── route53.tf
│
├── alb.tf
├── ecs.tf
├── ecr.tf
│
├── dynamodb.tf
├── iam.tf
│
├── backend.tf
└── versions.tf
```

For larger configurations, use modules:

```text
terraform/
│
├── modules/
│   ├── networking/
│   ├── frontend/
│   ├── cloudfront/
│   ├── alb/
│   ├── ecs/
│   ├── ecr/
│   ├── dynamodb/
│   └── iam/
│
└── environments/
    ├── dev/
    ├── staging/
    └── prod/
```

Do not introduce modules prematurely. Use modules when there is meaningful reuse or when the configuration becomes difficult to maintain.

---

## 7. Naming Convention

Use predictable resource names.

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

Avoid random resource names unless AWS requires uniqueness.

Use Terraform-generated identifiers only when necessary.

---

## 8. Tags

All taggable AWS resources should use consistent tags.

Example:

```hcl
locals {
  common_tags = {
    Project     = "online-tutoring"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}
```

Resources should use:

```hcl
tags = local.common_tags
```

Additional resource-specific tags may be added when useful.

Recommended tags:

```text
Project
Environment
ManagedBy
Owner
Component
```

---

## 9. Variables

Do not hard-code environment-specific values.

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
* DynamoDB configuration
* Container image
* Application ports

Example:

```hcl
variable "aws_region" {
  description = "AWS region for the application"
  type        = string
  default     = "us-east-1"
}
```

Variables should include:

* Description
* Type
* Default value when appropriate
* Validation when appropriate

---

## 10. Sensitive Variables

Sensitive values must not be hard-coded in Terraform files.

Never commit:

```text
AWS access keys
AWS secret keys
Passwords
API keys
Database credentials
Private keys
Application secrets
```

Use AWS Secrets Manager, SSM Parameter Store, or CI/CD secret management where appropriate.

Example:

```hcl
variable "api_secret" {
  type      = string
  sensitive = true
}
```

Do not place secrets in:

* `.tf` files
* `.tfvars` committed to Git
* Dockerfiles
* GitHub repositories
* buildspec files

---

## 11. tfvars

Use environment-specific variable files when needed.

Example:

```text
terraform.tfvars
dev.tfvars
staging.tfvars
prod.tfvars
```

Sensitive `.tfvars` files must not be committed.

Add them to `.gitignore` when appropriate:

```text
*.tfvars
*.tfvars.json
```

A safe example file can be committed:

```text
terraform.tfvars.example
```

---

## 12. VPC Standards

The VPC should be designed for a private backend architecture.

Recommended:

```text
VPC
│
├── Public Subnets
│   └── ALB
│
└── Private Subnets
    └── ECS Fargate
```

Use multiple Availability Zones for production.

Example:

```text
Availability Zone A
├── Public Subnet
└── Private Subnet

Availability Zone B
├── Public Subnet
└── Private Subnet
```

Do not deploy ECS tasks directly into public subnets unless there is a specific architectural requirement.

---

## 13. NAT Gateway

Use NAT Gateway when private ECS tasks require outbound internet access.

For cost-conscious development environments, a single NAT Gateway may be acceptable.

Production environments should consider multi-AZ NAT architecture based on availability requirements and cost.

Do not create multiple NAT Gateways automatically without considering the project's cost requirements.

---

## 14. Security Groups

Security groups should follow least privilege.

Example:

```text
Internet
   │
   ▼
ALB Security Group
   │
   ▼
ECS Security Group
```

The ECS security group should allow inbound application traffic from the ALB security group rather than from `0.0.0.0/0`.

Avoid:

```hcl
cidr_blocks = ["0.0.0.0/0"]
```

for internal application traffic unless explicitly required.

---

## 15. S3 Frontend

The React frontend is hosted in S3.

The S3 bucket should:

* Block public access
* Use encryption
* Enable versioning where appropriate
* Be accessed through CloudFront
* Avoid direct public website access

CloudFront should be the public entry point.

Preferred flow:

```text
User
 │
 ▼
CloudFront
 │
 ▼
S3
 │
 ▼
React
```

Do not make the S3 bucket publicly readable merely to make the website work.

---

## 16. CloudFront

CloudFront is responsible for:

* CDN delivery
* HTTPS
* Frontend caching
* Routing frontend requests
* Routing API requests when configured with multiple origins

The CloudFront distribution should use the ACM certificate created in `us-east-1`.

HTTP should redirect to HTTPS.

Example:

```text
Viewer
 │
 │ HTTP
 ▼
CloudFront
 │
 │ Redirect
 ▼
HTTPS
```

---

## 17. ACM

ACM certificates must be managed through Terraform.

There are two important certificate requirements.

### CloudFront

The CloudFront ACM certificate must be created in:

```text
us-east-1
```

Example:

```hcl
resource "aws_acm_certificate" "cloudfront" {
  provider          = aws.us_east_1
  domain_name       = var.domain_name
  validation_method = "DNS"
}
```

### ALB

The ALB certificate must be created in the same region as the ALB.

Do not use the CloudFront certificate directly on an ALB in another region.

---

## 18. Route 53

Route 53 manages DNS records for the application.

Preferred architecture:

```text
Route 53
   │
   ▼
CloudFront
```

Use alias records when supported.

Avoid hard-coding CloudFront IP addresses.

---

## 19. ALB

The Application Load Balancer handles backend API traffic.

Preferred flow:

```text
CloudFront
    │
    ▼
   ALB
    │
    ▼
ECS Fargate
```

The ALB should:

* Use HTTPS
* Use an ACM certificate
* Forward traffic to an ECS target group
* Perform health checks
* Redirect HTTP to HTTPS when appropriate

---

## 20. ECS Fargate

The Python backend runs on ECS Fargate.

Example:

```text
ECS Cluster
│
└── Tutoring API Service
    │
    ├── Task
    │   └── Python Container
    │
    └── Task
        └── Python Container
```

The backend should be stateless.

Persistent data should be stored in:

* DynamoDB
* S3
* Other appropriate managed services

Do not depend on local container storage for persistent application data.

---

## 21. ECR

ECR stores the Python backend Docker images.

Preferred flow:

```text
CodeBuild
    │
    ▼
Docker Build
    │
    ▼
ECR
    │
    ▼
ECS Fargate
```

Use immutable image tags when possible.

Avoid relying exclusively on:

```text
latest
```

Prefer versioned tags such as:

```text
v1.0.0
commit-abc123
build-123
```

---

## 22. DynamoDB

DynamoDB is the primary application database.

Potential data:

```text
Students
Tutors
Courses
Classes
Enrollments
Bookings
Messages
```

Terraform should manage:

* Tables
* Billing configuration
* Encryption
* Point-in-time recovery where required
* Tags
* Appropriate indexes

The backend accesses DynamoDB through its ECS task IAM role.

The React frontend must never contain AWS credentials for direct DynamoDB access unless a deliberately designed client-side architecture requires it.

---

## 23. IAM

Use dedicated IAM roles for each AWS workload.

Examples:

```text
Terraform Deployment Role
        │
        └── Infrastructure permissions

ECS Task Execution Role
        │
        └── ECS infrastructure operations

ECS Task Role
        │
        └── Application permissions

CodeBuild Role
        │
        └── Build/deployment permissions

CodePipeline Role
        │
        └── Pipeline permissions
```

Do not use one broad IAM role for every service.

Follow least privilege.

---

## 24. ECS IAM Access to DynamoDB

The ECS task role should have only the DynamoDB actions required by the application.

For example:

```text
dynamodb:GetItem
dynamodb:PutItem
dynamodb:UpdateItem
dynamodb:DeleteItem
dynamodb:Query
dynamodb:Scan
```

Only grant the actions actually required.

Where possible, restrict the policy to specific DynamoDB table ARNs instead of:

```text
Resource = "*"
```

---

## 25. Terraform State

Terraform state must not be committed to Git.

Never commit:

```text
terraform.tfstate
terraform.tfstate.backup
```

For team or CI/CD usage, use a remote backend such as:

```text
S3
```

with appropriate state protection and locking supported by the selected Terraform/AWS configuration.

The state may contain sensitive infrastructure information and must be protected.

---

## 26. Terraform Workflow

Use the standard workflow:

```text
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
Review
        │
        ▼
terraform apply
```

Before committing:

```bash
terraform fmt -check
terraform validate
```

A plan should be reviewed before applying infrastructure changes.

---

## 27. Formatting

Terraform files must be formatted with:

```bash
terraform fmt
```

Do not manually maintain inconsistent formatting.

CI/CD should validate formatting.

---

## 28. Validation

Run:

```bash
terraform validate
```

after configuration changes.

Validation should be part of CI/CD.

Recommended pipeline:

```text
GitHub
   │
   ▼
CodeBuild
   │
   ├── terraform fmt -check
   ├── terraform init
   ├── terraform validate
   └── terraform plan
```

---

## 29. Plan Before Apply

Never automatically apply major infrastructure changes without reviewing the Terraform plan.

Use:

```bash
terraform plan
```

to identify:

* Resources to create
* Resources to modify
* Resources to destroy
* IAM changes
* Networking changes
* Security group changes
* Database changes

Pay special attention to destructive changes involving:

* DynamoDB
* S3
* VPC
* ECS
* ALB
* CloudFront
* ACM
* Route 53

---

## 30. Resource Lifecycle

Use lifecycle rules only when there is a clear reason.

Example:

```hcl
lifecycle {
  prevent_destroy = true
}
```

may be appropriate for critical production resources such as important DynamoDB tables.

Do not add `prevent_destroy` indiscriminately because it can make legitimate infrastructure changes difficult.

---

## 31. Dependencies

Prefer implicit Terraform dependencies.

Example:

```hcl
load_balancer {
  target_group_arn = aws_lb_target_group.app.arn
}
```

Use `depends_on` only when Terraform cannot determine the dependency automatically.

Avoid unnecessary:

```hcl
depends_on = [...]
```

---

## 32. Data Sources

Use data sources when referencing existing AWS resources.

Examples:

```hcl
data "aws_caller_identity" "current" {}
```

```hcl
data "aws_route53_zone" "main" {
  name = var.domain_name
}
```

Do not recreate an existing resource simply because Terraform does not currently manage it.

If an existing resource should become Terraform-managed, use an appropriate import process.

---

## 33. Outputs

Outputs should expose useful infrastructure information.

Examples:

```hcl
output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.frontend.domain_name
}
```

```hcl
output "alb_dns_name" {
  value = aws_lb.app.dns_name
}
```

```hcl
output "ecr_repository_url" {
  value = aws_ecr_repository.backend.repository_url
}
```

Do not output secrets.

---

## 34. Comments

Comments should explain **why**, not simply repeat what the Terraform code does.

Good:

```hcl
# CloudFront requires ACM certificates to be created in us-east-1.
provider = aws.us_east_1
```

Avoid:

```hcl
# Create certificate
resource "aws_acm_certificate" ...
```

The resource name already explains what it does.

---

## 35. Security Requirements

Terraform configurations must:

* Avoid hard-coded credentials
* Avoid public S3 access unless explicitly required
* Avoid unrestricted security group rules
* Use encryption where supported
* Use IAM least privilege
* Keep ECS tasks private where practical
* Use HTTPS for public application traffic
* Use ACM for certificates
* Protect Terraform state
* Avoid exposing secrets through outputs

---

## 36. Cost Requirements

The tutoring platform is initially an MVP.

Terraform should avoid unnecessary AWS resources.

Cost-conscious decisions may include:

* Single NAT Gateway for development
* Small ECS task sizes
* Minimal ECS desired count for development
* DynamoDB on-demand billing for unpredictable MVP traffic
* Appropriate CloudFront caching
* Avoiding unnecessary NAT gateways
* Avoiding unnecessary load balancers
* Removing unused development resources

Production availability requirements should take priority over cost when appropriate.

---

## 37. Environment Separation

The project should eventually support:

```text
dev
staging
prod
```

Example:

```text
tutoring-dev
tutoring-staging
tutoring-prod
```

Environment-specific values should come from variables rather than duplicated Terraform code.

---

## 38. Git Requirements

Do not commit:

```text
.terraform/
*.tfstate
*.tfstate.*
*.tfvars
*.tfvars.json
crash.log
```

Recommended `.gitignore`:

```text
.terraform/
*.tfstate
*.tfstate.*
*.tfvars
*.tfvars.json
crash.log
override.tf
override.tf.json
*_override.tf
*_override.tf.json
```

Do commit:

```text
*.tf
README.md
terraform.tfvars.example
buildspec*.yml
```

---

## 39. Change Management

Before modifying infrastructure:

1. Understand the existing architecture.
2. Identify dependencies.
3. Modify the smallest number of resources necessary.
4. Run `terraform fmt`.
5. Run `terraform validate`.
6. Run `terraform plan`.
7. Review destructive changes carefully.
8. Apply the change.
9. Verify the AWS resources.
10. Update documentation when architecture changes.

---

## 40. Kiro Agent Rules

When modifying Terraform for this project, the agent should:

1. Inspect the existing Terraform configuration before creating new resources.
2. Reuse existing variables, locals, resources, and modules when appropriate.
3. Avoid creating duplicate resources.
4. Follow the existing naming conventions.
5. Follow least-privilege IAM principles.
6. Keep ECS backend resources private where practical.
7. Keep the S3 frontend bucket private.
8. Use CloudFront as the frontend public entry point.
9. Use ACM for HTTPS.
10. Remember that the CloudFront ACM certificate belongs in `us-east-1`.
11. Keep the ALB ACM certificate in the ALB's AWS region.
12. Use DynamoDB for persistent application data.
13. Never put AWS credentials in application code or Terraform files.
14. Run formatting and validation after Terraform changes.
15. Review `terraform plan` before applying changes.
16. Do not destroy existing resources unless the requested change requires it.
17. Do not introduce additional AWS services without a clear project requirement.
18. Prefer simple, maintainable Terraform over unnecessary abstraction.

---

## 41. Target Infrastructure

The final Terraform-managed infrastructure should follow this architecture:

```text
                              USERS
                                │
                                │ HTTPS
                                ▼
                         ┌──────────────┐
                         │   Route 53   │
                         │     DNS      │
                         └──────┬───────┘
                                │
                                ▼
                         ┌──────────────┐
                         │  CloudFront  │
                         │     CDN      │
                         │              │
                         │ ACM Cert     │
                         └──────┬───────┘
                                │
                  ┌─────────────┴─────────────┐
                  │                           │
               /* │                        /api/*
                  │                           │
                  ▼                           ▼
           ┌─────────────┐             ┌─────────────┐
           │     S3      │             │     ALB     │
           │ React       │             │    HTTPS    │
           │ Frontend    │             │ ACM Cert    │
           └─────────────┘             └──────┬──────┘
                                              │
                                              ▼
                                       ┌──────────────┐
                                       │ ECS Fargate  │
                                       │              │
                                       │ Python API   │
                                       └──────┬───────┘
                                              │
                                              ▼
                                       ┌──────────────┐
                                       │   DynamoDB   │
                                       │              │
                                       │ Students     │
                                       │ Tutors       │
                                       │ Classes      │
                                       │ Bookings     │
                                       └──────────────┘


                         ┌──────────────┐
                         │     ECR      │
                         │ Python API   │
                         │ Docker Image │
                         └──────┬───────┘
                                │
                                ▼
                           ECS Fargate


                         ┌──────────────┐
                         │  Terraform   │
                         │              │
                         │ VPC          │
                         │ S3           │
                         │ CloudFront   │
                         │ ACM          │
                         │ Route 53     │
                         │ ALB          │
                         │ ECS          │
                         │ ECR          │
                         │ DynamoDB     │
                         │ IAM          │
                         └──────────────┘
```

---

## 42. Core Principle

The Terraform configuration should remain:

### **Secure → Simple → Repeatable → Reviewable → Cost-conscious → Maintainable**

Infrastructure changes should be predictable and reproducible across environments.
