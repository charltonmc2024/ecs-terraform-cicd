# Erudition Solution — Product Context

## Purpose

Erudition Solution is an adaptive educational assessment platform for school districts.

Students take practice assessments aligned with state standardized testing. Questions adapt to student performance, while teachers can review student progress and assessment results.

---

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

---

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

Security, reliability, availability, and operational controls may vary by environment based on requirements and cost.

---

## Current Environment Scope

The current implementation target is the development environment only.

Terraform deployment root:

`ecs-terraform/envs/dev/`

Do not create:

- `envs/staging/`
- `envs/prod/`

unless explicitly requested.

Reusable modules should remain environment-independent where practical so additional environments can be added later without redesigning the core architecture.

Do not create staging or production resources merely for future compatibility.

---

## Current Development Goal

Complete a working end-to-end development environment containing the infrastructure required to run, deploy, secure, and observe the application.

### Networking

- VPC
- Public subnets
- Private subnets
- Internet Gateway
- Optional NAT Gateway
- Required VPC endpoints
- Security groups

Application workloads should run in private subnets.

### Edge

- Private S3 frontend bucket
- CloudFront distribution
- Origin Access Control (OAC)
- CloudFront VPC Origin

For the current DEV environment:

- use the default `*.cloudfront.net` domain
- use the CloudFront default viewer certificate
- do not require Route 53
- do not require a custom ACM certificate
- keep the frontend S3 bucket private
- keep the application ALB internal

Route 53, custom domains, and custom ACM certificates may be introduced for future environments when explicitly required.

AWS Shield Standard automatically provides baseline DDoS protection for supported services such as CloudFront and requires no separate Terraform resource.

### Backend

- ECR
- Internal Application Load Balancer
- Target groups
- ALB listener
- ECS Fargate cluster
- ECS task definition
- ECS service
- ECS execution role
- ECS task role
- Secrets integration
- Auto Scaling
- Application log groups

ECS tasks should run in private subnets and should not receive public IP addresses.

### Data

- DynamoDB
- Required DynamoDB indexes
- Backup configuration
- KMS where justified
- Schema documentation

### CI/CD

- Jenkins
- Docker image build
- ECR image push
- ECS application deployment
- Terraform validation and planning
- Deployment verification

Jenkins is the primary CI/CD platform unless another platform is explicitly requested.

### Observability and Security Operations

Add appropriate controls as the development environment progresses, including where required:

- CloudWatch
- SNS
- WAF
- CloudTrail
- GuardDuty
- AWS Config

These services should be introduced according to the approved observability/security design rather than added automatically for architectural complexity.

WAF is optional for the current DEV environment unless explicitly enabled.

---

## High-Level Application Architecture

The current DEV request path is:

```text
Internet
   |
CloudFront
   |
   +---- Private S3 Frontend via OAC
   |
   +---- CloudFront VPC Origin
                |
          Internal ALB
                |
          ECS Fargate
                |
            DynamoDB
```

CloudFront is the public application entry point.

The S3 frontend, internal ALB, ECS workloads, and application data resources should remain private according to their architectural roles.

---

## Future Environments

Staging and production are outside the current implementation scope.

When explicitly introduced, they may add or strengthen capabilities such as:

- custom domains
- Route 53
- ACM certificates
- AWS WAF
- stronger monitoring and alerting
- additional logging and auditing
- customer-managed KMS keys where justified
- backup and recovery controls
- high-availability controls
- disaster-recovery capabilities
- stricter CI/CD approval gates
- environment-specific security and compliance controls

Do not assume DEV-specific cost or security decisions automatically apply to staging or production.

---

## Technology

### Application

- Next.js
- Node.js
- TypeScript
- Docker

### Infrastructure

- AWS
- Terraform

### Compute

- ECS Fargate

### Data

- DynamoDB

### CI/CD

- Jenkins

---

## Cost Principle

Prefer the lowest-cost architecture that satisfies development, security, reliability, and learning requirements.

Optional resources with meaningful recurring cost should be configurable where practical.

Do not add AWS services simply to make the architecture more complex.

Do not sacrifice required security controls merely to reduce cost.

Every significant service or recurring-cost resource should have a clear architectural, security, operational, reliability, or product purpose.