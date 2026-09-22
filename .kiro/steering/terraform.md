# Terraform Conventions

## General Principles

-   Manage AWS infrastructure with Terraform.
-   Prefer reusable and maintainable Terraform over duplicated
    configuration.
-   Avoid hardcoding values that should be variables, locals, resource
    references, or data-source values.
-   Prefer least-privilege IAM.
-   Keep the infrastructure cost-conscious while meeting application
    requirements.
-   Do not create a one-to-one AWS server replacement merely because a
    server exists in the legacy QA environment.

## Naming

Use the shared application/environment prefix for resources when
appropriate.

``` hcl
locals {
  name_prefix = "${var.app_name}-${var.environment}"
}
```

Prefer:

``` hcl
name = "${local.name_prefix}-resource"
```

instead of repeatedly constructing:

``` hcl
name = "${var.app_name}-${var.environment}-resource"
```

Use Terraform references instead of manually copying AWS ARNs or
generated identifiers.

## Shared Tags

Use consistent tags for AWS resources where supported.

Typical tags include:

-   Project
-   Environment
-   ManagedBy
-   Owner

Prefer shared tags through provider `default_tags` and/or
`local.common_tags` rather than repeating tag maps unnecessarily.

## Variables

Use variables for environment-specific or configurable values such as:

-   AWS region
-   Application name
-   Environment
-   VPC CIDR
-   Public/private subnet CIDRs
-   ECS task CPU
-   ECS task memory
-   ECS desired task count
-   Container port
-   Health-check path

Do not hardcode these values throughout resource definitions.

## Providers

Use the normal AWS provider for resources in the deployment region.

When CloudFront-related ACM resources require `us-east-1`, use an
aliased AWS provider for that region.

## Networking

-   ALB belongs in public subnets.
-   ECS Fargate tasks belong in private subnets.
-   ECS services should not receive public IP addresses.
-   ECS security groups should accept application traffic from the ALB
    security group rather than from `0.0.0.0/0`.
-   Use NAT Gateway egress when private workloads require outbound
    internet access.

## ECS

-   Use Fargate for the target backend architecture.
-   Use `awsvpc` networking.
-   Keep ECS container names consistent between task definitions and ECS
    service load-balancer configuration.
-   Store images in ECR.
-   Send container logs to CloudWatch.
-   Use the ECS task execution role for ECS/Fargate execution
    requirements.
-   Use a separate task/application IAM role when the application needs
    AWS API permissions.

## ALB

-   Use an Application Load Balancer for backend API traffic.
-   Use target groups with `target_type = "ip"` for Fargate tasks.
-   Configure health checks using the application's health-check path.
-   Use HTTPS for production public traffic.
-   Redirect HTTP to HTTPS where appropriate.

## DynamoDB

-   DynamoDB is the target application database.
-   Base table and index design on application access patterns.
-   Enable encryption.
-   Enable point-in-time recovery where required by the project design.
-   Grant DynamoDB access through the ECS task IAM role.
-   Never expose database access directly to the frontend.

## S3 and CloudFront

-   Keep frontend S3 buckets private.
-   Use CloudFront as the public delivery layer.
-   Use an appropriate CloudFront origin-access mechanism.
-   Use ACM certificates for HTTPS.
-   CloudFront ACM certificates must be in `us-east-1`.

## IAM

-   Follow least privilege.
-   Separate execution permissions from application permissions.
-   Do not embed credentials in Terraform code, application source, or
    container images.
-   Reference IAM roles and policies through Terraform resources
    whenever possible.

## Terraform State

Keep bootstrap/state infrastructure separate from the main application
infrastructure.

The main Terraform configuration should use remote state rather than
relying on local state for shared/deployed environments.

Do not commit sensitive state files or credentials to source control.

## Validation

Before applying changes, use the normal Terraform workflow:

``` bash
terraform fmt
terraform validate
terraform plan
```

Review the plan before applying infrastructure changes.

## Architecture References

For detailed target architecture, see:

`docs/AWS-Production-Deployment.md`

For the existing/legacy QA environment, see:

`docs/QA-Environment-Specifications.md`
