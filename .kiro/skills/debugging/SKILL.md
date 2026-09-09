# Debugging Skill

## Purpose

Use this skill when diagnosing, troubleshooting, isolating, or fixing problems in the Online Tutoring Platform.

This skill covers:

* React frontend problems
* Python backend problems
* API failures
* ECS/Fargate problems
* ALB problems
* CloudFront problems
* S3 problems
* DynamoDB problems
* IAM problems
* Terraform problems
* CI/CD problems
* Docker/ECR problems
* Networking problems
* DNS/Route 53 problems
* ACM/HTTPS problems
* CloudWatch/logging problems

Project architecture and infrastructure standards are defined by the Steering files:

* `project-overview.md`
* `aws-architecture.md`
* `terraform-standards.md`

These Steering files take precedence over assumptions made in this skill.

---

# Debugging Principles

1. Do not guess the root cause.
2. Reproduce the problem whenever practical.
3. Collect evidence before changing configuration.
4. Start with the simplest possible explanation.
5. Debug from the outside in.
6. Identify which layer is failing.
7. Change one relevant thing at a time.
8. Make the smallest safe change.
9. Verify the fix after making the change.
10. Do not hide errors by weakening monitoring or tests.
11. Do not grant excessive IAM permissions as a first solution.
12. Do not destroy infrastructure to solve an unknown problem.
13. Preserve useful logs and error messages.
14. Add a regression test for important bugs.
15. Document the root cause when the issue is significant.

---

# Debugging Workflow

Use this workflow:

```text
Observe
   ↓
Reproduce
   ↓
Collect Evidence
   ↓
Identify Layer
   ↓
Form Hypothesis
   ↓
Test Hypothesis
   ↓
Apply Smallest Fix
   ↓
Verify
   ↓
Regression Test
   ↓
Document
```

Do not skip directly from an error message to a large infrastructure change.

---

# Application Architecture Debugging

Use the application request path:

```text
Browser
   │
   ▼
Route 53
   │
   ▼
CloudFront
   │
   ├──► S3
   │      └── React
   │
   └──► ALB
          │
          ▼
        ECS
          │
          ▼
        Python
          │
          ▼
      DynamoDB
```

When something fails, determine the last layer that is known to be working.

Example:

```text
Frontend loads
       ↓
CloudFront works
       ↓
API request fails
       ↓
Investigate CloudFront / ALB / ECS
```

Do not immediately investigate DynamoDB if the request never reaches ECS.

---

# First Response to Any Error

Capture:

```text
Exact error message
Time of failure
AWS region
AWS account
Environment
Resource name
Recent changes
Deployment version
Relevant logs
```

Check Git:

```bash
git status
git log -5 --oneline
git diff
```

Determine whether the problem started after a recent change.

---

# Debugging by Layer

## Layer 1 — Browser / React

Check:

* Browser console
* Network tab
* HTTP status
* Request URL
* Request method
* Request headers
* Response body
* CORS errors
* JavaScript errors
* Frontend environment configuration

Common symptoms:

```text
404
401
403
500
CORS error
Network error
Blank page
Old frontend version
```

Determine whether the failure is:

```text
Frontend code
API request
CloudFront
Backend
Authentication
```

---

# Layer 2 — CloudFront

If the frontend or API behaves unexpectedly, verify:

* Distribution status
* Origin
* Origin path
* Cache behavior
* Path pattern
* `/api/*` behavior
* HTTPS configuration
* ACM certificate
* Cache policy
* Origin request policy
* Response headers policy

For frontend caching issues, determine whether the problem is:

```text
S3 content
CloudFront cache
Browser cache
```

Do not change multiple CloudFront settings simultaneously.

---

# Layer 3 — S3

For frontend deployment problems verify:

```bash
aws s3 ls s3://<frontend-bucket>
```

Check:

* Files exist
* Correct build was uploaded
* Correct bucket is configured as the CloudFront origin
* Bucket is not unintentionally public
* CloudFront can access the bucket

If S3 contains the correct files but the browser shows old files, investigate caching before rebuilding the application.

---

# Layer 4 — ALB

For API problems check:

```text
CloudFront
   ↓
ALB
   ↓
Target Group
   ↓
ECS
```

Verify:

* Listener
* Listener rules
* Target group
* Target port
* Health-check path
* Health-check port
* Target health
* Security groups

If the target is unhealthy, debug ECS/container connectivity before debugging application business logic.

---

# Layer 5 — ECS

Check ECS service:

```bash
aws ecs describe-services \
  --cluster <cluster-name> \
  --services <service-name> \
  --region us-east-1 \
  --profile CharltonCICD
```

Check:

* Desired count
* Running count
* Pending count
* Deployment status
* Service events

Check tasks:

```bash
aws ecs list-tasks \
  --cluster <cluster-name> \
  --service-name <service-name> \
  --region us-east-1 \
  --profile CharltonCICD
```

Then inspect the task:

```bash
aws ecs describe-tasks \
  --cluster <cluster-name> \
  --tasks <task-arn> \
  --region us-east-1 \
  --profile CharltonCICD
```

Look for:

* Task stopped reason
* Container exit code
* Container reason
* Image pull failure
* Health-check failure
* Network failure
* IAM failure

---

# ECS Task Stopped

If a task stops unexpectedly, investigate in this order:

```text
Task stopped reason
       ↓
Container exit code
       ↓
CloudWatch logs
       ↓
Application startup
       ↓
Environment variables
       ↓
IAM
       ↓
Network
```

Common causes:

* Application crash
* Incorrect startup command
* Missing dependency
* Incorrect environment variable
* Incorrect container port
* Failed health check
* Insufficient permissions
* Image problem

Do not increase CPU or memory blindly.

First determine why the process stopped.

---

# Layer 6 — Python Backend

Check:

* Application startup logs
* Stack traces
* Environment variables
* Dependency versions
* Port binding
* API route
* Request validation
* Exception handling
* AWS SDK configuration

For an API failure determine:

```text
Request received?
        │
        ├── No → Network / ALB / ECS
        │
        └── Yes
             ↓
        Application error?
             │
             ├── Yes → Python debugging
             │
             └── No
                  ↓
              DynamoDB?
```

---

# Layer 7 — DynamoDB

If the backend cannot access DynamoDB, verify:

```text
ECS Task
   ↓
Task IAM Role
   ↓
DynamoDB
```

Check:

* Table name
* AWS region
* IAM task role
* Required DynamoDB actions
* Key schema
* Item structure
* Conditional operations
* Throttling/errors

Common IAM errors include:

```text
AccessDeniedException
ResourceNotFoundException
ValidationException
```

Do not solve `AccessDeniedException` by giving the task `AdministratorAccess`.

Identify the exact missing action and resource.

---

# Layer 8 — IAM

For `AccessDenied` errors determine:

```text
Who?
 ↓
What AWS API call?
 ↓
Which resource?
 ↓
Which IAM policy?
 ↓
Which role?
```

Distinguish between:

```text
Terraform execution role
CI/CD role
CodeBuild role
ECS task execution role
ECS task role
```

Do not confuse the ECS task execution role with the ECS application task role.

---

# Layer 9 — Docker

If ECS cannot start the container, test locally when practical.

Build:

```bash
docker build -t tutoring-backend .
```

Run:

```bash
docker run --rm -p 8000:8000 tutoring-backend
```

Verify the application locally.

If the image fails locally, fix the Docker/application problem before debugging ECS.

Check:

* Base image
* Dependencies
* Dockerfile
* Startup command
* Working directory
* Port
* Environment variables
* File paths

---

# Layer 10 — ECR

If ECS cannot pull the image, check:

* ECR repository
* Image tag
* Image digest
* ECS task execution role
* ECR permissions
* Network connectivity
* Region

Verify the image exists:

```bash
aws ecr describe-images \
  --repository-name <repository> \
  --region us-east-1 \
  --profile CharltonCICD
```

Do not assume `latest` refers to the image you intended to deploy.

Prefer immutable tags.

---

# Layer 11 — Terraform

When Terraform fails:

```bash
terraform fmt
terraform validate
terraform plan
```

Read the complete error.

Determine whether it is:

```text
Syntax
Provider
Dependency
Reference
Variable
Resource
IAM
Network
State
AWS API
```

Check Terraform state when appropriate:

```bash
terraform state list
```

Do not manually edit Terraform state unless there is a specific, understood reason.

Do not run:

```bash
terraform destroy
```

as a generic troubleshooting step.

---

# Terraform Unexpected Changes

If `terraform plan` shows unexpected changes:

1. Stop.
2. Do not immediately apply.
3. Identify the resource.
4. Compare configuration with state.
5. Determine whether AWS was changed outside Terraform.
6. Determine whether a Terraform change caused the difference.
7. Check lifecycle settings.
8. Review dependencies.
9. Confirm whether replacement is required.

Pay special attention to:

```text
DynamoDB
S3
CloudFront
Route 53
VPC
ECS
ALB
```

because unintended replacement can cause service disruption or data loss.

---

# Networking Debugging

Use the network path:

```text
Internet
   ↓
CloudFront
   ↓
ALB
   ↓
ECS Private Subnet
   ↓
AWS Services
```

Check:

* VPC
* Subnet
* Route table
* Internet Gateway
* NAT Gateway
* Security Group
* Network ACL
* ALB listener
* Target group
* ECS ENI

For private ECS tasks that need outbound internet access, verify the expected NAT Gateway and route table configuration.

Do not make private ECS tasks publicly accessible merely to solve connectivity problems.

---

# Security Group Debugging

Use least privilege.

Expected model:

```text
Internet
   ↓
ALB Security Group
   ↓
ECS Security Group
```

The ECS security group should generally allow application traffic from the ALB security group rather than from the entire internet.

When debugging a connection:

```text
Source
 ↓
Destination
 ↓
Protocol
 ↓
Port
 ↓
Security Group
 ↓
Route
```

Identify the exact blocked connection.

---

# DNS Debugging

For Route 53 problems check:

```text
Domain
 ↓
DNS record
 ↓
CloudFront
 ↓
Application
```

Verify:

* Hosted zone
* Record name
* Record type
* Alias target
* CloudFront distribution
* DNS propagation
* HTTPS certificate

Do not change DNS records repeatedly without determining the current record state.

---

# ACM / HTTPS Debugging

If HTTPS fails, check:

```text
Certificate status
 ↓
Domain coverage
 ↓
CloudFront/ALB attachment
 ↓
DNS
 ↓
Listener
```

Remember:

```text
CloudFront certificate → us-east-1
ALB certificate → ALB's AWS region
```

Do not create another certificate until the existing certificate configuration has been inspected.

---

# CloudWatch Debugging

Use CloudWatch logs to establish what actually happened.

Look for:

```text
Timestamp
Request
Error
Stack trace
Container restart
AWS API error
Timeout
```

Correlate the timestamp with:

* Deployment
* ECS task replacement
* API request
* ALB health check
* Terraform operation

Never rely solely on the last log message.

---

# CI/CD Debugging

Pipeline:

```text
GitHub
   ↓
CodePipeline
   ↓
Test
   ↓
Build
   ↓
Deploy
```

Identify the first stage that failed.

Do not debug Deploy if Test failed.

Do not debug ECS if the image was never successfully pushed to ECR.

Use:

```text
First failing stage
       ↓
Build logs
       ↓
Exact command
       ↓
Exact error
       ↓
Root cause
```

---

# Build Failure Debugging

For CodeBuild failures inspect:

* Build phase
* Exact command
* Environment variables
* IAM permissions
* Docker availability
* ECR authentication
* Dependency installation
* Terraform version
* AWS region

Do not modify multiple buildspec phases at once.

---

# Deployment Failure Debugging

Use:

```text
Pipeline
   ↓
Which stage failed?
   ↓
Which command failed?
   ↓
Which AWS service?
   ↓
Which resource?
   ↓
Which permission/configuration?
```

For ECS deployment:

```text
ECR image exists?
      ↓
Task definition valid?
      ↓
ECS task starts?
      ↓
Container stays running?
      ↓
ALB target healthy?
      ↓
API responds?
```

---

# 429 / Rate-Limit Debugging

When Docker or another external service returns:

```text
429 Too Many Requests
```

determine:

* Which service returned 429
* Which account/IP was rate-limited
* Whether the build is repeatedly pulling the same image
* Whether the dependency can be cached
* Whether ECR should be used instead
* Whether the failure is transient

Do not blindly retry indefinitely.

For Docker base images, consider the project's approved ECR/caching strategy when appropriate.

---

# Error Classification

Classify errors before fixing them.

## Code Error

Examples:

```text
Exception
TypeError
SyntaxError
Failed test
```

Fix application code.

## Configuration Error

Examples:

```text
Wrong port
Wrong environment variable
Wrong table name
Wrong API URL
```

Fix configuration.

## IAM Error

Examples:

```text
AccessDeniedException
UnauthorizedOperation
```

Fix the appropriate IAM policy.

## Network Error

Examples:

```text
Timeout
Connection refused
No route
Unhealthy target
```

Investigate networking and security groups.

## Infrastructure Error

Examples:

```text
ResourceNotFound
InvalidSubnet
CloudFormation failure
Terraform plan failure
```

Investigate AWS/Terraform configuration.

## Dependency Error

Examples:

```text
Package unavailable
Version conflict
Docker registry failure
```

Investigate dependencies or external services.

---

# Root Cause Analysis

For significant problems, document:

```text
Problem:
What failed?

Impact:
What was affected?

Root Cause:
Why did it fail?

Evidence:
What proved the root cause?

Fix:
What changed?

Verification:
How was the fix confirmed?

Prevention:
What test or control prevents recurrence?
```

Avoid documenting only the symptom.

Example:

```text
Problem:
ECS tasks repeatedly stopped.

Root Cause:
Container startup command referenced a module that did not exist.

Fix:
Corrected the application startup command.

Verification:
Container remained running and ALB health check passed.

Prevention:
Added container startup testing to CI.
```

---

# Debugging Rules for Kiro

When debugging:

1. Read the Steering files first.
2. Inspect the existing implementation.
3. Reproduce the issue.
4. Capture the exact error.
5. Identify the failing layer.
6. Check logs and AWS state.
7. Form a hypothesis.
8. Test the hypothesis.
9. Make the smallest fix.
10. Run the relevant tests.
11. Verify the deployment when applicable.
12. Add a regression test for important bugs.
13. Do not make unrelated improvements during a debugging task.
14. Do not hide errors.
15. Do not claim the issue is fixed without verification.

---

# Debugging Decision Tree

```text
Problem
   │
   ▼
Can it be reproduced?
   │
   ├── No → Collect logs/evidence
   │
   └── Yes
        ↓
Where does it fail?
        │
        ├── Browser
        │
        ├── CloudFront
        │
        ├── ALB
        │
        ├── ECS
        │
        ├── Python
        │
        ├── DynamoDB
        │
        ├── IAM
        │
        ├── Network
        │
        ├── Terraform
        │
        └── CI/CD
             ↓
        Identify root cause
             ↓
        Smallest safe fix
             ↓
        Test
             ↓
        Verify
             ↓
        Regression protection
```

---

# Definition of Done

A debugging task is complete when:

* [ ] Problem reproduced or sufficient evidence collected
* [ ] Failing layer identified
* [ ] Root cause identified
* [ ] Fix implemented
* [ ] Relevant tests pass
* [ ] Infrastructure validated if applicable
* [ ] Deployment verified if applicable
* [ ] No unrelated changes introduced
* [ ] No excessive IAM permissions added
* [ ] No secrets exposed
* [ ] Regression test added when appropriate
* [ ] Root cause documented for significant incidents

---

# Core Debugging Workflow

```text
Observe
   ↓
Reproduce
   ↓
Collect Evidence
   ↓
Locate Failing Layer
   ↓
Identify Root Cause
   ↓
Apply Smallest Fix
   ↓
Test
   ↓
Deploy if Required
   ↓
Verify
   ↓
Prevent Recurrence
```
