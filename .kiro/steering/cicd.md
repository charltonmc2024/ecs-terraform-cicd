# Jenkins CI/CD Standards

## CI/CD Platform

Jenkins is the primary CI/CD platform.

Do not introduce CodePipeline or another CI/CD platform unless
explicitly requested.

## Current Deployment Target

Jenkins currently targets only:

`envs/dev`

Terraform working directory:

`ecs-terraform/envs/dev`

Do not implement staging or production pipeline stages unless
explicitly requested.

## Jenkinsfile

The main pipeline definition belongs at the repository root:

`Jenkinsfile`

Do not place the primary Jenkinsfile inside the Terraform module.

## Pipeline Flow

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

## Terraform Pipeline

Run:

`terraform fmt -check -recursive`
`terraform init`
`terraform validate`
`terraform plan`

Terraform validation or planning failures must fail the pipeline.

Do not automatically apply infrastructure changes without an
intentional deployment control.

## Application Pipeline

Typical stages:

1. Checkout source
2. Install dependencies
3. Run tests
4. Build application
5. Build Docker image
6. Authenticate to ECR
7. Push Docker image
8. Update ECS deployment
9. Verify deployment

## Docker Images

Prefer immutable image tags.

Examples:

- Git commit SHA
- Jenkins build number

Do not rely exclusively on:

`latest`

for controlled deployments.

## Credentials

Never hardcode AWS credentials in the Jenkinsfile.

Use:

- IAM roles where possible
- Jenkins Credentials
- Secrets Manager where appropriate

## ECR

Jenkins may:

- authenticate to ECR
- build the application image
- tag the image
- push the image

## ECS

Deploy the intended immutable image version to ECS.

Deployment failures must fail the pipeline.

## Failure Handling

Do not silently ignore failures.

Failures in:

- tests
- Terraform validation
- Terraform plan
- Docker build
- ECR push
- ECS deployment

must stop the appropriate pipeline execution.