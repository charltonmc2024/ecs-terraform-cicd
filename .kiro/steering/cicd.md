# Jenkins CI/CD Standards

## CI/CD Platform

Jenkins is the primary CI/CD platform.

Do not introduce AWS CodePipeline, GitHub Actions, or another CI/CD platform unless explicitly requested.

Jenkins pipeline behavior belongs in the repository `Jenkinsfile`.

Terraform modules may create infrastructure required by Jenkins, but they must not contain the primary application deployment pipeline.

---

## Current Deployment Target

Jenkins currently targets only:

`envs/dev`

Terraform working directory:

`ecs-terraform/envs/dev`

Do not implement staging or production pipeline stages unless explicitly requested.

Future staging and production pipelines may introduce additional approval, security, testing, and deployment controls without changing the fundamental module architecture.

---

## Jenkinsfile

The main pipeline definition belongs at the repository root:

`Jenkinsfile`

Do not place the primary Jenkinsfile inside a Terraform module.

Keep pipeline logic understandable and avoid unnecessary duplication.

Use scripts or reusable pipeline components only when they provide a clear maintainability benefit.

---

## Pipeline Flow

The intended high-level flow is:

```text
Git
 |
Jenkins
 |
 +-- Application Tests
 |
 +-- Terraform Checks
 |
 +-- Docker Build
 |
 +-- ECR Push
 |
 +-- ECS Deployment
 |
 +-- Deployment Verification
```

A failure in a required stage must prevent dependent deployment stages from continuing.

---

## Terraform Pipeline

Run appropriate Terraform quality and planning checks including:

```bash
terraform fmt -check -recursive
terraform init
terraform validate
terraform plan
```

Terraform formatting, initialization, validation, or planning failures must fail the appropriate pipeline execution.

Do not automatically run `terraform apply` merely because `terraform plan` succeeds.

Infrastructure changes require an intentional deployment control.

For the current DEV workflow, infrastructure planning and application deployment should remain logically distinguishable.

Future staging and production environments may require stronger approval gates before infrastructure changes are applied.

---

## Terraform State

Use the configured remote Terraform backend for environment state.

Do not create or maintain separate local state as part of the Jenkins deployment workflow.

Do not commit:

- `terraform.tfstate`
- `terraform.tfstate.backup`
- saved Terraform plan files
- `.terraform/`

Jenkins must use the correct backend and environment before running Terraform operations.

---

## Application Pipeline

Typical application deployment stages are:

1. Checkout source
2. Install dependencies
3. Run tests
4. Build application
5. Build Docker image
6. Authenticate to ECR
7. Tag Docker image with an immutable identifier
8. Push Docker image to ECR
9. Deploy the intended image version to ECS
10. Verify deployment

Do not deploy an application image if required tests or build stages fail.

---

## Docker Images

Prefer immutable image tags.

Examples:

- Git commit SHA
- Jenkins build number

Do not rely exclusively on:

`latest`

for controlled deployments.

The deployed ECS task definition should identify the intended application image version.

Using `latest` as an optional convenience tag is acceptable only when deployment does not depend on it for version identification.

---

## Credentials

Never hardcode AWS credentials in the Jenkinsfile, Terraform configuration, Dockerfiles, or application source.

Prefer:

- IAM roles where possible
- Jenkins Credentials where required
- AWS Secrets Manager where appropriate

Use least-privilege permissions for Jenkins.

Do not grant Jenkins `AdministratorAccess` merely to simplify deployment.

Do not expose credentials or secret values in pipeline logs.

---

## ECR

Jenkins may:

- authenticate to ECR
- build the application image
- tag the image
- push the image

Use the ECR repository created and managed by the appropriate Terraform module.

Do not hardcode ECR repository URLs when they can be obtained from Terraform outputs, AWS APIs, environment configuration, or other established project interfaces.

---

## ECS

Deploy the intended immutable image version to ECS.

ECS deployment must use the existing architecture:

- ECS Fargate
- private subnets
- no public IP assignment
- internal ALB
- existing ECS service and task-definition architecture

The CI/CD pipeline must not make architectural changes merely to simplify deployment.

Deployment failures must fail the pipeline.

Do not silently continue after an unsuccessful ECS deployment.

---

## Deployment Verification

After an ECS deployment, verify that the deployment reaches a healthy state.

Verification should confirm appropriate signals such as:

- ECS service deployment status
- desired tasks are running
- failed tasks are detected
- ALB target health where applicable

Application-level verification may be added where appropriate.

For the current architecture, public application verification should use the intended CloudFront entry point rather than exposing the internal ALB or ECS tasks publicly.

---

## Failure Handling

Do not silently ignore failures.

Failures in required stages such as:

- application tests
- Terraform formatting
- Terraform initialization
- Terraform validation
- Terraform plan
- Docker build
- ECR authentication
- ECR push
- ECS deployment
- deployment verification

must stop the appropriate pipeline execution.

Do not use failure-suppression patterns solely to force a pipeline to appear successful.

Log enough information to diagnose failures without exposing secrets.

---

## Infrastructure vs Application Deployment

Treat infrastructure changes and application releases as related but distinct concerns.

Terraform manages AWS infrastructure.

The application deployment workflow builds an immutable container image, pushes it to ECR, and deploys the intended image version to ECS.

Do not run `terraform apply` for every application release unless the architecture explicitly requires Terraform to manage that deployment action.

Do not modify infrastructure merely to deploy a new application image.

---

## Environment Guidance

### Development

Current CI/CD automation targets only:

`ecs-terraform/envs/dev`

DEV should remain simple, secure, and cost-conscious.

Infrastructure changes should be reviewed through Terraform plan before intentional application.

Application deployments may be automated after required tests and checks succeed.

### Staging and Production

Do not create staging or production pipelines unless explicitly requested.

When those environments are introduced, evaluate additional controls such as:

- manual approval gates
- protected branches
- environment-specific credentials and IAM roles
- stronger test requirements
- deployment health checks
- rollback strategies
- change-management requirements
- infrastructure approval controls
- production monitoring and alerting

Do not assume DEV deployment controls automatically apply to staging or production.