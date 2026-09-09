# Testing Skill

## Purpose

Use this skill when creating, modifying, running, reviewing, or troubleshooting tests for the Online Tutoring Platform.

This skill covers:

* React frontend testing
* Python backend testing
* API testing
* Terraform validation and testing
* AWS infrastructure verification
* Integration testing
* CI/CD testing
* Deployment smoke testing
* Regression testing

Project architecture and infrastructure standards are defined by the Steering files:

* `project-overview.md`
* `aws-architecture.md`
* `terraform-standards.md`

These Steering files take precedence over assumptions made in this skill.

---

# Testing Principles

1. Test before deployment whenever practical.
2. Test the smallest relevant scope first.
3. Do not modify production infrastructure simply to make a test pass.
4. Never use production student data for automated tests.
5. Use test fixtures and mock data.
6. Keep tests repeatable.
7. Tests should fail clearly when behavior is incorrect.
8. Do not disable tests to hide failures.
9. Infrastructure tests must not accidentally destroy shared resources.
10. Deployment tests must verify actual service health.
11. Fix the root cause instead of weakening the test.
12. Every important production failure should result in a regression test when practical.

---

# Testing Workflow

Use:

```text
Inspect
   ↓
Identify Test Scope
   ↓
Run Existing Tests
   ↓
Add/Update Tests
   ↓
Run Tests
   ↓
Analyze Failures
   ↓
Fix
   ↓
Run Regression Tests
   ↓
Validate
```

Do not immediately modify application code when a test fails.

First determine whether the failure is caused by:

* Application code
* Test code
* Configuration
* Environment
* AWS infrastructure
* Dependencies
* Network connectivity
* IAM permissions

---

# Test Levels

The project should use multiple testing levels:

```text
Unit Tests
    ↓
Component Tests
    ↓
API Tests
    ↓
Integration Tests
    ↓
Infrastructure Tests
    ↓
Deployment Smoke Tests
```

Not every change requires every test level.

Use the smallest sufficient test scope first, then expand testing for higher-risk changes.

---

# Frontend Testing

The frontend is the React application.

Test:

* Components
* Forms
* Navigation
* API calls
* Error handling
* Loading states
* Authentication behavior
* Responsive behavior where practical
* User interactions

Examples of important scenarios:

```text
Student opens dashboard
Student views tutoring content
Student submits a request
Student receives API response
API failure is displayed correctly
Loading state is displayed
Invalid input is rejected
```

Avoid testing implementation details when behavior-based testing is sufficient.

---

# Backend Testing

The backend is the Python application.

Test:

* API endpoints
* Request validation
* Response structure
* Business logic
* Error handling
* Authentication/authorization
* DynamoDB interactions
* Configuration handling

Important API scenarios include:

```text
Valid request
Invalid request
Missing required field
Unauthorized request
Forbidden request
Resource not found
Successful resource creation
Successful resource retrieval
Server-side failure
```

Tests should verify both successful and unsuccessful behavior.

---

# API Testing

Every important API endpoint should have tests for:

```text
200 Success
400 Bad Request
401 Unauthorized
403 Forbidden
404 Not Found
500 Internal Server Error
```

Only test status codes that the endpoint is actually designed to return.

Verify:

* HTTP status
* Response body
* Response schema
* Required fields
* Error format
* Headers where relevant

---

# DynamoDB Testing

Do not make automated tests depend on production DynamoDB data.

Preferred options:

```text
Unit Test
   ↓
Mock DynamoDB client
```

or:

```text
Integration Test
   ↓
Dedicated Test Table
```

Test:

* Create
* Read
* Update
* Delete
* Query
* Validation
* Missing records
* Conditional operations
* Error handling

Test data should be isolated from development and production data.

---

# Terraform Testing

Terraform changes must pass:

```bash
terraform fmt -check
terraform validate
terraform plan
```

Basic workflow:

```bash
terraform fmt
terraform validate
terraform plan
```

Review the plan for:

* Unexpected resource creation
* Unexpected resource destruction
* Security group changes
* IAM changes
* Network changes
* Replacement of stateful resources
* DynamoDB table destruction
* S3 bucket destruction
* CloudFront replacement
* ECS service replacement

A successful Terraform plan does not automatically mean the architecture is correct.

---

# Terraform Safety Tests

Pay particular attention to stateful resources:

```text
DynamoDB
S3
ECR
```

Before approving a plan that destroys or replaces one of these resources:

1. Identify why replacement is occurring.
2. Determine whether data will be lost.
3. Check whether the resource has a deletion protection strategy.
4. Review the Terraform diff.
5. Stop and request approval if the change is destructive and unexpected.

Never automatically approve:

```text
destroy
replace
delete
```

when the impact is unclear.

---

# AWS Infrastructure Verification

After Terraform deployment, verify important resources.

Check:

```text
VPC
Subnets
Route Tables
NAT Gateway
Security Groups
ALB
Target Groups
ECS Cluster
ECS Service
ECS Tasks
ECR
S3
CloudFront
ACM
Route 53
DynamoDB
IAM
CloudWatch
```

Infrastructure testing should verify actual AWS state rather than relying only on Terraform output.

---

# ECS Testing

After deployment verify:

```text
Desired Count
Running Count
Pending Count
Task Status
Task Health
Container Health
Target Group Health
```

A deployment should not be considered successful just because the ECS service update command completed.

The expected condition is:

```text
Desired Tasks = Running Tasks
Pending Tasks = 0
ALB Targets = Healthy
```

---

# ALB Testing

Test the backend through the ALB/CloudFront application path rather than testing only the container directly.

Verify:

```text
Client
  ↓
CloudFront
  ↓
ALB
  ↓
Target Group
  ↓
ECS
  ↓
Python API
```

Check:

* HTTPS
* Routing
* Health check
* Target health
* API response
* Error handling

---

# CloudFront Testing

For frontend deployments verify:

1. CloudFront distribution is enabled.
2. S3 origin is correct.
3. HTTPS works.
4. Frontend files are available.
5. React routing works.
6. `/api/*` routes to the backend when configured.
7. Cached content is updated when required.

Test both:

```text
https://example.com/
```

and API paths such as:

```text
https://example.com/api/health
```

when that routing pattern is configured.

---

# ACM Testing

Verify:

* Certificate status is issued.
* Certificate covers the required domain.
* CloudFront uses the certificate in `us-east-1`.
* ALB uses the correct regional certificate.
* HTTPS connections succeed.

Do not assume a certificate is working simply because ACM reports `ISSUED`.

Test the actual HTTPS endpoint.

---

# Route 53 Testing

Verify:

```text
Domain
   ↓
Route 53
   ↓
CloudFront
   ↓
Application
```

Test:

* DNS resolution
* Correct record
* HTTPS
* Expected CloudFront distribution
* No accidental routing to an old environment

---

# Security Testing

Check for:

* Public S3 buckets
* Public ECS tasks
* Open ECS security groups
* Unnecessary ALB ports
* Overly broad IAM permissions
* Secrets committed to Git
* Credentials inside Docker images
* Credentials in frontend JavaScript
* Unencrypted sensitive configuration

Never place AWS credentials in:

```text
React source
Dockerfile
Git repository
Terraform variables committed to Git
Frontend environment variables
```

Remember that React build-time environment variables become part of the client-side application and should therefore be treated as public.

---

# CI/CD Testing

The CodePipeline workflow should test before deployment:

```text
GitHub
  ↓
Source
  ↓
Test
  ↓
Build
  ↓
Deploy
```

The Test stage should fail the pipeline when required tests fail.

Example:

```text
Test Failed
     ↓
Pipeline Stops
     ↓
No Deployment
```

Do not allow failed tests to proceed to production deployment unless an explicit exception is approved.

---

# Test Categories for CI/CD

Recommended pipeline checks:

```text
Frontend
├── Dependency installation
├── Lint
├── Unit tests
└── Build

Backend
├── Dependency installation
├── Lint
├── Unit tests
├── API tests
└── Package/build

Terraform
├── Format check
├── Validate
└── Plan
```

The exact commands should follow the project's package manager and testing framework.

Do not invent commands if the repository already defines them.

Inspect:

```text
package.json
pyproject.toml
requirements.txt
pytest configuration
Makefile
buildspec files
```

before creating new commands.

---

# Deployment Smoke Tests

After deployment, run lightweight smoke tests.

Minimum checks:

```text
Frontend loads
       ↓
HTTPS works
       ↓
API health endpoint works
       ↓
Backend responds
       ↓
DynamoDB access works
```

Smoke tests should be fast and should not modify production data unnecessarily.

Example:

```text
GET /health
```

Expected result:

```text
HTTP 200
```

---

# Regression Testing

When fixing a bug:

```text
Reproduce
   ↓
Create regression test
   ↓
Fix bug
   ↓
Run regression test
   ↓
Run related tests
```

Do not only verify that the bug disappeared manually.

The regression test should prevent the same problem from returning.

---

# Testing After Infrastructure Changes

Use targeted testing.

For example:

### Security Group change

Test:

```text
ALB → ECS connectivity
ECS → DynamoDB connectivity
Unintended inbound access
```

### CloudFront change

Test:

```text
Frontend
API routing
HTTPS
Caching
```

### ECS change

Test:

```text
Task startup
Container health
ALB target health
API response
Logs
```

### DynamoDB change

Test:

```text
IAM permissions
Table access
Application CRUD operations
```

### Route 53 change

Test:

```text
DNS resolution
HTTPS
Correct CloudFront destination
```

---

# Failure Investigation

When a test fails, collect evidence before changing code.

For AWS failures inspect:

```text
Terraform output
AWS service status
ECS service events
ECS task stopped reason
CloudWatch logs
ALB target health
Security groups
IAM policies
CloudFront configuration
DynamoDB status
```

Classify the failure:

```text
Code
Configuration
Infrastructure
IAM
Network
Dependency
Test
Environment
```

Then fix the appropriate layer.

---

# Test Data

Use clearly identifiable test data.

Example:

```text
environment = test
student_id = test-student-001
course_id = test-course-001
```

Never use real student information in automated tests.

Clean up temporary test resources after integration tests where practical.

---

# Performance Testing

Performance testing should be introduced after functional correctness is established.

Potential targets:

```text
API latency
ECS response time
DynamoDB latency
CloudFront cache performance
Frontend load time
```

Do not perform aggressive load testing against production without explicit approval.

---

# Cost-Aware Testing

Testing should not unnecessarily create expensive AWS resources.

Before creating test infrastructure, determine whether the test can use:

* Local unit tests
* Mocks
* Existing development resources
* Temporary test resources
* Dedicated low-cost test tables

Avoid creating duplicate production-sized infrastructure solely for a simple test.

---

# Definition of Done

A change is considered tested when:

* [ ] Relevant unit tests pass
* [ ] Relevant integration/API tests pass
* [ ] Terraform formatting passes
* [ ] Terraform validation passes
* [ ] Terraform plan reviewed when infrastructure changed
* [ ] Security implications reviewed
* [ ] Deployment smoke tests pass
* [ ] ECS tasks are healthy when backend changed
* [ ] ALB targets are healthy when backend changed
* [ ] CloudFront works when frontend changed
* [ ] DynamoDB access works when database integration changed
* [ ] No secrets are exposed
* [ ] Regression test added for important bug fixes
* [ ] No unexpected destructive infrastructure changes exist

---

# Kiro Agent Behavior

When performing a testing task:

1. Read the Steering files first.
2. Inspect the existing test structure.
3. Identify the smallest relevant test scope.
4. Run existing tests before making changes when practical.
5. Do not rewrite working tests unnecessarily.
6. Add tests for new behavior.
7. Add regression tests for important bugs.
8. Never disable a failing test just to make the pipeline pass.
9. Separate application failures from infrastructure failures.
10. Validate Terraform changes before deployment.
11. Verify deployed AWS resources after deployment.
12. Report the exact test failure and likely root cause.
13. Do not claim success without actual test results.

---

# Core Testing Workflow

```text
Read Steering
      ↓
Inspect Existing Tests
      ↓
Identify Scope
      ↓
Run Tests
      ↓
Analyze Failure
      ↓
Fix / Add Test
      ↓
Run Regression Tests
      ↓
Validate Infrastructure
      ↓
Deploy
      ↓
Smoke Test
      ↓
Verify
```
