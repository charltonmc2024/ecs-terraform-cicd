# Erudition Solution — AWS Architecture

## Current Scope

Implement only:

`envs/dev`

Do not create staging or production environments unless explicitly requested.

## High-Level Request Flow

For DEV, CloudFront is the public entry point on its default
`*.cloudfront.net` domain. Route 53 and a custom ACM certificate are
NOT part of the current DEV request flow; they are future
custom-domain concerns (see Edge Module).

Internet
   |
CloudFront   (default *.cloudfront.net domain)
   |
   +---- Default behavior ----> S3 Frontend (private, via OAC)
   |
   +---- /api/* ----> CloudFront VPC Origin
                          |
                     Internal ALB (internal)
                          |
                     ECS Fargate (private subnets)
                          |
             (NAT egress / TLS, outbound)
                          |
                     MongoDB Atlas (external managed service, M0)

The database is MongoDB Atlas, provisioned outside Terraform via the Atlas
console. Private ECS tasks reach it outbound over TLS through the NAT
Gateway (Atlas M0 has no VPC peering/PrivateLink); the connection URI
comes from AWS Secrets Manager, injected as MONGODB_URL. No database
resource runs inside the VPC and there is no Terraform data module.

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

- Private S3 frontend bucket
- CloudFront distribution
- Origin Access Control (OAC)
- CloudFront VPC Origin

The S3 frontend bucket must remain private.

CloudFront should access S3 through Origin Access Control.

The CloudFront distribution's default behavior serves the private S3
frontend; the `/api/*` behavior routes through the edge-owned
CloudFront VPC Origin to the internal ALB. The edge module consumes
`alb_arn` and `alb_dns_name` from the backend module to build the VPC
Origin (no ALB ARN, DNS name, or VPC Origin id is hardcoded).

For DEV, CloudFront uses its default `*.cloudfront.net` domain and the
default viewer certificate; the edge module creates NO ACM certificate
and NO Route 53 resources.

ACM and Route 53 are future custom-domain capabilities: a later
environment may add a custom viewer domain, a Route 53 hosted zone and
records, and a custom ACM certificate in `us-east-1` (via the
`aws.us_east_1` provider alias) without redesigning the module. None of
these are created for DEV.

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
- ECS cluster
- ECS task definition
- ECS service
- ECS execution role
- ECS task role
- Secrets integration
- Auto Scaling
- CloudWatch application log groups

The backend module does NOT own the CloudFront VPC Origin; that
resource belongs to the edge module. The backend module exposes
`alb_arn` and `alb_dns_name` so the edge module can build the
CloudFront VPC Origin and set the API origin domain. The backend
module holds no reference to the edge module.

ECS tasks should run in private subnets.

ECS tasks should not receive public IP addresses.

## Data (MongoDB Atlas — no Terraform module)

The application database is MongoDB Atlas (M0 free tier for development),
an external managed service provisioned manually through the Atlas console
outside Terraform. There is NO `modules/data/` Terraform module — it was
removed when the project standardized on MongoDB Atlas as the only database.

Responsibilities (handled outside Terraform / by the application):

- Atlas M0 cluster, database, and database users — created in the Atlas console.
- Connection URI — stored in AWS Secrets Manager and injected into the ECS
  task as `MONGODB_URL` (the backend module wires this via `app_secret_arn`).
- MongoDB indexes — created by the application at startup (`init_db()`), not
  by Terraform.
- Network reachability — private ECS tasks egress to Atlas over the NAT
  Gateway's stable IP, which is added to the Atlas IP access list.

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
      v
   backend
      |
      v
    edge

The network module is upstream of the backend module; the backend
module is upstream of the edge module. The edge module consumes
`alb_arn` and `alb_dns_name` from the backend module. The backend
module never references the edge module. There is no data module (the
database is external MongoDB Atlas), so no module depends on one.

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