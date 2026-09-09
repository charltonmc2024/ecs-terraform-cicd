# AWS Deployment Skill

## Purpose

Use this skill when deploying, updating, verifying, troubleshooting, or rolling back the Online Tutoring Platform on AWS.

This skill covers application deployment and AWS service integration.

Project architecture and infrastructure standards are defined by the Steering files:

* `project-overview.md`
* `aws-architecture.md`
* `terraform-standards.md`

These Steering files take precedence over assumptions made in this skill.

---

# Target AWS Architecture

The application uses:

```text
User
  │
  ▼
Route 53
  │
  ▼
CloudFront
  ├──► S3
  │     └── React Frontend
  │
  └──► ALB
        │
        ▼
      ECS Fargate
        │
        ├──► DynamoDB
        │
        └──► Other AWS Services
```

Supporting services:

* ACM
* ECR
* VPC
* Public/private subnets
* Security Groups
* IAM
* CloudWatch
* CodePipeline
* CodeBuild

---

# Deployment Principles

1. Infrastructure is managed by Terraform.
2. Application code is deployed through CI/CD.
3. Do not manually modify Terraform-managed infrastructure unless necessary for emergency recovery.
4. Never expose DynamoDB directly to the frontend.
5. ECS tasks should run in private subnets.
6. ALB should be publicly accessible only where required.
7. S3 frontend content should not require public bucket access.
8. Secrets must not be committed to Git.
9. IAM permissions should follow least privilege.
10. Deployment changes should be verified after every release.
11. Prefer the smallest change necessary.
12. Do not destroy production resources to solve deployment problems unless explicitly approved.

---

# Deployment Flow

Use this general workflow:

```text
Code Change
    │
    ▼
Git Push
    │
    ▼
CodePipeline
    │
    ├──► Test
    │
    ├──► Build Frontend
    │       └──► Upload to S3
    │
    ├──► Build Backend
    │       └──► Docker Image
    │             └──► Push to ECR
    │
    └──► Deploy
            │
            ├──► CloudFront/S3
            │
            └──► ECS
                  │
                  ▼
              Health Check
```

---

# Pre-Deployment Checks

Before deploying, inspect:

```bash
git status
git branch
git log -1
```

Verify the expected branch is being deployed.

Check AWS identity:

```bash
aws sts get-caller-identity --profile CharltonCICD
```

Check the AWS region:

```bash
aws configure get region --profile CharltonCICD
```

Expected project region:

```text
us-east-1
```

Verify Terraform:

```bash
terraform version
```

Run:

```bash
terraform fmt -check
terraform validate
terraform plan
```

Do not deploy infrastructure if `terraform plan` contains unexpected destructive changes.

---

# Frontend Deployment

The frontend is the React application.

Build the frontend using the project's configured package manager.

Typical workflow:

```bash
npm install
npm run build
```

The generated static files should be uploaded to the configured S3 frontend bucket.

Example:

```bash
aws s3 sync ./build s3://<frontend-bucket> --delete
```

Do not make the S3 bucket public merely to make the frontend work.

CloudFront should provide the public access path.

---

# CloudFront Deployment

After frontend deployment:

1. Verify the S3 origin.
2. Verify CloudFront distribution configuration.
3. Verify the CloudFront domain.
4. Verify HTTPS.
5. Verify the ACM certificate.
6. Verify the `/api/*` behavior if configured.
7. Invalidate cached frontend objects when necessary.

Example:

```bash
aws cloudfront create-invalidation \
  --distribution-id <distribution-id> \
  --paths "/*"
```

Do not invalidate CloudFront unnecessarily because caching is part of the architecture.

---

# Backend Deployment

The backend runs as a Docker container on ECS Fargate.

Deployment workflow:

```text
Python Backend
      │
      ▼
Docker Build
      │
      ▼
ECR
      │
      ▼
ECS Task Definition
      │
      ▼
ECS Service
      │
      ▼
ALB
```

Build the image:

```bash
docker build -t tutoring-backend .
```

Authenticate with ECR:

```bash
aws ecr get-login-password --region us-east-1 \
  --profile CharltonCICD |
  docker login \
  --username AWS \
  --password-stdin <account-id>.dkr.ecr.us-east-1.amazonaws.com
```

Tag the image:

```bash
docker tag tutoring-backend:latest \
  <account-id>.dkr.ecr.us-east-1.amazonaws.com/<repository>:<tag>
```

Push:

```bash
docker push \
  <account-id>.dkr.ecr.us-east-1.amazonaws.com/<repository>:<tag>
```

Prefer immutable image tags for deployments.

Examples:

```text
git-<commit-sha>
release-001
release-002
```

Avoid relying exclusively on:

```text
latest
```

---

# ECS Deployment

After the image is available in ECR:

1. Update the ECS task definition.
2. Reference the new container image.
3. Register the new task definition revision.
4. Update the ECS service.
5. Wait for ECS deployment stabilization.
6. Verify running tasks.
7. Verify ALB target health.
8. Test the backend API.

Useful commands:

```bash
aws ecs describe-services \
  --cluster <cluster-name> \
  --services <service-name> \
  --region us-east-1 \
  --profile CharltonCICD
```

Check running tasks:

```bash
aws ecs list-tasks \
  --cluster <cluster-name> \
  --service-name <service-name> \
  --region us-east-1 \
  --profile CharltonCICD
```

Describe a task:

```bash
aws ecs describe-tasks \
  --cluster <cluster-name> \
  --tasks <task-arn> \
  --region us-east-1 \
  --profile CharltonCICD
```

---

# ECS Deployment Verification

A deployment is not complete merely because ECS reports a new task.

Verify:

```text
ECS Service
    │
    ├── Desired count = expected
    ├── Running count = expected
    ├── Pending count = 0
    │
    ▼
ALB Target Group
    │
    └── Targets = healthy
    │
    ▼
API Endpoint
    │
    └── HTTP response = expected
```

Check ECS service events when deployment fails.

Check CloudWatch logs when containers fail.

---

# ALB Verification

Verify:

* ALB exists.
* Listener exists.
* HTTPS is configured where required.
* ACM certificate is attached.
* Target group exists.
* ECS tasks are registered.
* Targets are healthy.
* Health-check path is valid.

A common health-check endpoint should be lightweight, for example:

```text
/health
```

The endpoint should return a successful HTTP response when the application is healthy.

---

# DynamoDB Verification

DynamoDB is accessed by the backend.

Deployment verification should confirm:

```text
ECS Task
   │
   ▼
Task IAM Role
   │
   ▼
DynamoDB
```

Do not put AWS access keys inside:

* React code
* Docker images
* Git repositories
* `.env` files committed to Git

Use the ECS task IAM role for AWS API access.

Verify that the task role has only the DynamoDB permissions required by the application.

---

# IAM Verification

When a deployment fails with `AccessDenied`, determine:

1. Which AWS principal made the request.
2. Which AWS API operation failed.
3. Which resource was accessed.
4. Which IAM policy should provide access.
5. Whether the permission belongs to the deployment role or ECS task role.

Do not immediately grant:

```text
Action: "*"
Resource: "*"
```

Instead, identify the exact missing permission.

---

# CloudWatch Verification

For ECS application failures, inspect CloudWatch logs.

Check:

* Container startup
* Application exceptions
* Port binding
* Environment variables
* AWS SDK errors
* DynamoDB errors
* Health-check failures
* Out-of-memory errors
* Task termination messages

The application should log useful diagnostic information without logging secrets.

Never log:

* AWS access keys
* passwords
* tokens
* session credentials
* sensitive student information

---

# Deployment Troubleshooting

## ECS task immediately stops

Check:

```text
ECS task stopped reason
Container exit code
CloudWatch logs
Task definition
Environment variables
Container port
IAM task role
```

Common causes:

* Application startup error
* Incorrect command
* Incorrect container port
* Missing environment variable
* IAM permission failure
* Invalid secret
* Container health-check failure

---

## ALB target is unhealthy

Check:

```text
Security Group
    ↓
ALB → ECS connectivity
    ↓
Container port
    ↓
Health-check path
    ↓
Application response
```

Verify that the ECS security group allows traffic from the ALB security group on the application port.

Do not open the ECS security group to:

```text
0.0.0.0/0
```

unless explicitly required.

---

## Frontend loads but API fails

Check:

```text
Browser
  ↓
CloudFront
  ↓
/api/* behavior
  ↓
ALB
  ↓
ECS
  ↓
DynamoDB
```

Verify:

* CloudFront behavior
* ALB origin
* HTTPS configuration
* API path
* CORS
* ALB listener
* Target health
* ECS application port
* Security groups

---

## Frontend changes are not visible

Check:

1. New files exist in S3.
2. CloudFront distribution points to the correct bucket.
3. Browser cache.
4. CloudFront cache.
5. Required invalidation.

Do not assume that a successful S3 upload means CloudFront is immediately serving the new version.

---

# Rollback Strategy

If a deployment fails:

```text
Detect Failure
     │
     ▼
Stop Further Changes
     │
     ▼
Identify Failed Component
     │
     ├── Frontend
     └── Backend
     │
     ▼
Restore Previous Known-Good Version
     │
     ▼
Verify
```

For ECS:

* Prefer deploying the previous known-good image.
* Keep previous task-definition revisions available.
* Do not delete the previous working image immediately.

For frontend:

* Restore the previous known-good S3 build when necessary.
* Invalidate CloudFront only when required.

---

# Infrastructure vs Application Changes

Use Terraform for:

```text
VPC
Subnets
NAT Gateway
Security Groups
ALB
ECS Cluster
ECS Service
ECS Task Definition
ECR
S3
CloudFront
ACM
Route 53
DynamoDB
IAM
CloudWatch
```

Use CI/CD for:

```text
React build
Python application build
Docker image build
ECR push
Frontend S3 deployment
ECS application deployment
```

Do not mix application deployment commands into Terraform unless there is a clear architectural reason.

---

# CI/CD Deployment

The preferred deployment pipeline is:

```text
GitHub
   │
   ▼
CodePipeline
   │
   ├── Test
   │
   ├── Frontend Build
   │       │
   │       └──► S3
   │
   ├── Backend Build
   │       │
   │       └──► ECR
   │
   └── Deploy
           │
           └──► ECS
```

Each stage should have a clear responsibility.

Avoid making one buildspec responsible for unrelated infrastructure and application operations.

---

# Deployment Safety

Before production deployment:

```bash
git status
git diff
terraform plan
```

Confirm:

* Correct AWS account
* Correct AWS region
* Correct Git branch
* Correct ECR repository
* Correct ECS cluster
* Correct ECS service
* Correct S3 bucket
* Correct CloudFront distribution

Never assume an AWS resource belongs to the intended environment solely because its name looks correct.

---

# Environment Separation

When environments are introduced, use separate configuration for:

```text
dev
staging
prod
```

Do not hard-code production resource names into reusable Terraform modules.

Environment-specific values should come from Terraform variables, environment configuration, or approved CI/CD configuration.

---

# Cost Awareness

This project is intended to maintain a cost-conscious MVP architecture.

Before enabling expensive resources, consider:

* NAT Gateway cost
* ECS Fargate task count
* ALB cost
* CloudFront usage
* DynamoDB capacity mode
* CloudWatch log retention
* ECR storage
* S3 storage
* Data transfer

For development, avoid unnecessary always-on resources.

Do not add:

* additional NAT Gateways
* unnecessary ECS tasks
* unnecessary load balancers
* oversized Fargate tasks

without a clear requirement.

---

# Definition of Done

An AWS deployment is complete when:

* [ ] Correct AWS account confirmed
* [ ] Correct region confirmed
* [ ] Infrastructure is healthy
* [ ] Frontend build completed
* [ ] Frontend uploaded to S3
* [ ] CloudFront serves the frontend
* [ ] Backend image built
* [ ] Backend image pushed to ECR
* [ ] ECS deployment completed
* [ ] ECS tasks are running
* [ ] ALB targets are healthy
* [ ] API endpoint responds successfully
* [ ] ECS can access DynamoDB
* [ ] CloudWatch logs show no deployment-critical errors
* [ ] HTTPS works
* [ ] No secrets were exposed
* [ ] No unexpected infrastructure changes occurred
* [ ] Deployment can be rolled back

---

# Kiro Agent Behavior

When performing an AWS deployment task:

1. Read the project Steering files first.
2. Inspect the current AWS/Terraform configuration.
3. Determine whether the change is infrastructure or application related.
4. Use Terraform for infrastructure changes.
5. Use CI/CD/application deployment procedures for application changes.
6. Make the smallest safe change.
7. Validate before deployment.
8. Check the deployment result.
9. Inspect logs when something fails.
10. Never hide deployment errors.
11. Never claim deployment succeeded without verification.
12. Explain destructive or potentially expensive changes before executing them.

---

# Core AWS Deployment Workflow

```text
Read Steering
      ↓
Inspect Current State
      ↓
Identify Change
      ↓
Validate Configuration
      ↓
Build
      ↓
Deploy
      ↓
Monitor
      ↓
Verify
      ↓
Rollback if Necessary
```
