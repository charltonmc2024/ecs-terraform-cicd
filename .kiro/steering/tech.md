# Technology and Architecture

## Target AWS Architecture

Use the following target architecture:

-   Amazon S3 for React frontend hosting
-   Amazon CloudFront for CDN and HTTPS frontend delivery
-   AWS Certificate Manager (ACM) for TLS/SSL certificates
-   Amazon Route 53 for DNS
-   Application Load Balancer (ALB) for backend traffic routing
-   Amazon ECS with AWS Fargate for backend API containers
-   Amazon ECR for Docker container images
-   Amazon DynamoDB for application data
-   Amazon VPC for network isolation
-   AWS IAM for access control
-   Terraform for infrastructure as code
-   AWS CodePipeline and CodeBuild for CI/CD

## Request Flow

Frontend:

`User -> Route 53 -> CloudFront -> S3`

Backend API:

`User -> Route 53 -> CloudFront -> ALB -> ECS Fargate -> DynamoDB`

Container deployment:

`Backend Source -> Docker Image -> ECR -> ECS Fargate`

## Networking

-   Place the ALB in public subnets.
-   Place ECS Fargate tasks in private subnets.
-   Do not expose ECS task IP addresses directly to the internet.
-   Allow application traffic to ECS only from the ALB security group.
-   Use a NAT Gateway when private ECS tasks require outbound internet
    access.
-   Access DynamoDB through AWS APIs.

## Frontend

-   Keep the S3 frontend bucket private.
-   Do not enable public read access.
-   Allow CloudFront to access the S3 origin through an appropriate
    origin-access mechanism.
-   Users should access the frontend through CloudFront/custom DNS
    rather than directly through S3.

## HTTPS and Certificates

-   Use HTTPS for public application traffic.
-   Redirect HTTP to HTTPS where appropriate.
-   The ACM certificate used by CloudFront must be created in
    `us-east-1`.
-   An ALB HTTPS listener requires an ACM certificate in the same AWS
    region as the ALB.

## Backend

-   Package the backend as a Docker image.
-   Store backend images in Amazon ECR.
-   Run the backend using ECS Fargate.
-   Route API traffic through the ALB.
-   Do not allow the browser to connect directly to DynamoDB.

## DynamoDB

-   DynamoDB is the primary application database in the target
    architecture.
-   Design tables and indexes from actual application access patterns.
-   ECS should access DynamoDB using an IAM task role.
-   Grant only the DynamoDB permissions required by the application.

## IAM and Security

Use separate IAM roles where appropriate for:

-   ECS task execution
-   ECS application/task access
-   CodeBuild
-   CodePipeline
-   Terraform deployment

Follow least-privilege access.

Store secrets outside container images.

## CI/CD

Application deployment should be automated.

Frontend flow:

`GitHub -> CodePipeline -> CodeBuild -> S3 -> CloudFront`

Backend flow:

`GitHub -> CodePipeline -> CodeBuild -> ECR -> ECS Fargate`

Terraform manages AWS infrastructure separately from application
deployment.

## Future Services

Do not add optional services solely because they are available.
Potential future capabilities include Cognito, WAF, notifications,
payment processing, file storage, CloudWatch monitoring, X-Ray, ECS Auto
Scaling, and backup/disaster recovery. Add them when supported by an
application requirement.

## Detailed Reference

See `docs/AWS-Production-Deployment.md`.
