# Erudition Solution — AWS Architecture

## Current Scope

Implement only:

`envs/dev`

Do not create staging or production environments unless explicitly requested.

## High-Level Request Flow

Internet
   |
Route 53
   |
CloudFront
   |
   +---- S3 Frontend
   |
   +---- VPC Origin
            |
       Internal ALB
            |
       ECS Fargate
            |
        DynamoDB

AWS Shield Standard automatically provides baseline DDoS protection
for supported AWS services such as CloudFront.

No Terraform resource is required for Shield Standard.

## Network Module

Location:

`modules/network/`

Responsibilities:

- VPC
- Public subnets
- Private subnets
- Internet Gateway
- Route tables
- Route table associations
- NAT Gateway when enabled
- Elastic IP for NAT when required
- VPC endpoints
- ALB security group
- ECS security group
- VPC endpoint security group

Application workloads should run in private subnets.

## Edge Module

Location:

`modules/edge/`

Responsibilities:

- S3 frontend bucket
- CloudFront
- Origin Access Control
- ACM
- Route 53

The S3 frontend bucket must remain private.

CloudFront should access S3 through Origin Access Control.

AWS Shield Standard is automatic and must not be implemented as a
separate Terraform resource.

## Backend Module

Location:

`modules/backend/`

Responsibilities:

- ECR
- Internal ALB
- Target groups
- ALB listener
- CloudFront VPC Origin
- ECS cluster
- ECS task definition
- ECS service
- ECS execution role
- ECS task role
- Secrets integration
- Auto Scaling
- CloudWatch application log groups

ECS tasks should run in private subnets.

ECS tasks should not receive public IP addresses.

## Data Module

Location:

`modules/data/`

Responsibilities:

- DynamoDB
- DynamoDB indexes
- KMS where required
- Backup configuration
- Schema documentation

## CI/CD Module

Location:

`modules/cicd/`

Responsibilities:

- Infrastructure required to run Jenkins
- Jenkins IAM permissions
- Jenkins networking/security configuration

The Jenkins pipeline itself belongs in the repository `Jenkinsfile`.

## Observability Module

Location:

`modules/observability/`

Responsibilities:

- CloudWatch alarms
- CloudWatch dashboard
- SNS
- WAF
- GuardDuty
- CloudTrail
- AWS Config

## Dependency Direction

Prefer dependencies in this direction:

network
   |
   +---- backend
   |
   +---- data
   |
   +---- edge

backend
   |
   +---- edge

cicd
   |
   +---- deployment

observability
   |
   +---- monitors deployed resources

Avoid circular module dependencies.

## Architecture Principle

Do not change the established architecture merely to introduce
additional AWS services.

Architecture changes should have a clear security, reliability,
scalability, maintainability, cost, or product reason.