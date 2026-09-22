# Project Structure

## Repository Organization

Keep application code, Terraform infrastructure, Kiro steering, and
architecture documentation separated.

Recommended structure:

``` text
ecs-terraform-cicd/
├── .kiro/
│   └── steering/
│       ├── product.md
│       ├── tech.md
│       ├── structure.md
│       └── terraform.md
├── docs/
│   ├── AWS-Production-Deployment.md
│   └── QA-Environment-Specifications.md
├── ecs-application/
└── ecs-terraform/
    ├── bootstrap/
    ├── acm.tf
    ├── alb.tf
    ├── cloudfront.tf
    ├── cloudwatch.tf
    ├── dynamodb.tf
    ├── ecr.tf
    ├── ecs_cluster.tf
    ├── ecs_service.tf
    ├── ecs_task_definition.tf
    ├── eip.tf
    ├── iam.tf
    ├── iam_ecs.tf
    ├── igw.tf
    ├── listener.tf
    ├── locals.tf
    ├── natgw.tf
    ├── outputs.tf
    ├── provider.tf
    ├── route53.tf
    ├── variables.tf
    └── vpc.tf
```

## Directory Responsibilities

### `.kiro/steering/`

Contains durable instructions and project conventions that Kiro should
consistently follow.

Do not place large environment inventories or detailed architecture
documents here when they can live under `docs/`.

### `docs/`

Contains detailed project reference material.

-   `AWS-Production-Deployment.md` --- target AWS architecture and
    deployment design
-   `QA-Environment-Specifications.md` --- QA/legacy environment
    inventory and proposals

### `ecs-application/`

Contains backend/application source code and application-specific files.

### `ecs-terraform/`

Contains Terraform configuration for AWS infrastructure.

### `ecs-terraform/bootstrap/`

Contains infrastructure used to bootstrap Terraform remote state.

## Terraform File Organization

Prefer resource-oriented files rather than placing the entire
infrastructure in one large Terraform file.

Examples:

-   `vpc.tf` --- VPC
-   `igw.tf` --- Internet Gateway
-   `eip.tf` --- Elastic IP resources
-   `natgw.tf` --- NAT Gateway
-   `alb.tf` --- Application Load Balancer
-   `listener.tf` --- ALB listeners
-   `ecs_cluster.tf` --- ECS cluster
-   `ecs_service.tf` --- ECS service
-   `ecs_task_definition.tf` --- task definition
-   `ecr.tf` --- ECR repository
-   `dynamodb.tf` --- DynamoDB
-   `cloudfront.tf` --- CloudFront
-   `acm.tf` --- ACM certificates
-   `route53.tf` --- DNS
-   `iam.tf` / `iam_ecs.tf` --- IAM roles and policies
-   `cloudwatch.tf` --- logging/monitoring resources
-   `variables.tf` --- input variables
-   `locals.tf` --- shared local values
-   `outputs.tf` --- outputs
-   `provider.tf` --- Terraform and AWS provider configuration

## Documentation Rule

Do not duplicate the complete contents of architecture documents into
steering files. Steering should contain durable rules; detailed
inventories and architecture explanations should remain under `docs/`.
