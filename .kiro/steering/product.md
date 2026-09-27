# Erudition Solution — Product Context

## Purpose

Erudition Solution is an adaptive educational assessment platform for school districts.

Students take practice assessments aligned with state standardized testing.
Questions adapt to student performance, while teachers can review student
progress and assessment results.

## Primary Users

### Students
- Sign in securely.
- Take adaptive practice assessments.
- Submit answers.
- View appropriate results and progress.

### Teachers
- Sign in securely.
- View student progress.
- Review assessment performance.
- Monitor class-level results.

## Engineering Goals

The platform should be:

- Secure
- Scalable
- Highly available where appropriate
- Cost-conscious
- Observable
- Automated
- Maintainable
- Infrastructure-as-Code driven

## Current Environment Scope

The current implementation target is the development environment only.

Terraform deployment root:

`ecs-terraform/envs/dev/`

Do not create:

- `envs/staging/`
- `envs/prod/`

unless explicitly requested.

Reusable modules must remain environment-independent so additional
environments can be added later without redesigning the modules.

## Current Goal

Complete a working end-to-end development environment containing:

- VPC
- Public and private subnets
- Internet Gateway
- Optional NAT Gateway
- VPC endpoints
- Security groups
- S3 frontend
- CloudFront
- ACM
- Route 53
- AWS Shield Standard protection
- ECR
- Internal Application Load Balancer
- CloudFront VPC Origin
- ECS Fargate
- DynamoDB
- KMS where appropriate
- Secrets management
- Jenkins CI/CD
- CloudWatch
- SNS
- WAF
- CloudTrail
- GuardDuty
- AWS Config

## Technology

Application:
- Next.js
- Node.js
- TypeScript
- Docker

Infrastructure:
- AWS
- Terraform

Compute:
- ECS Fargate

Data:
- DynamoDB

CI/CD:
- Jenkins

## Cost Principle

Prefer the lowest-cost architecture that satisfies development,
security, reliability, and learning requirements.

Optional resources with meaningful recurring cost should be configurable
where practical.

Do not add AWS services simply to make the architecture more complex.