# AWS Security Standards

## Principle

Use least privilege and private-by-default architecture.

Security controls may vary by environment based on security, exposure, reliability, compliance, and cost requirements.

---

## IAM

Prefer IAM roles over IAM users.

Grant only the permissions required by each workload.

Avoid:

- `AdministratorAccess` for workloads
- unnecessary wildcard permissions
- long-lived AWS credentials
- credentials stored in source code

Separate responsibilities where appropriate.

Examples:

- ECS execution role
- ECS task role
- Jenkins role

---

## Network Security

Application workloads should run in private subnets.

ECS tasks must not receive public IP addresses unless explicitly required by a future architecture.

The application ALB should remain internal when accessed through CloudFront VPC Origin.

Prefer security-group-to-security-group rules where supported.

Avoid:

`0.0.0.0/0`

unless public access is intentionally required by the architecture.

Do not introduce public access solely as a workaround for missing private connectivity.

---

## Secrets

Never commit secrets to Git.

Never hardcode secrets inside:

- Terraform
- Dockerfiles
- Jenkinsfile
- application source
- committed `tfvars`

Use appropriate secret-management mechanisms such as:

- AWS Secrets Manager
- AWS Systems Manager Parameter Store
- Jenkins Credentials

Mark Terraform values as sensitive where appropriate.

---

## Encryption

Enable encryption where appropriate for:

- S3
- DynamoDB
- backups
- secrets
- CloudWatch Logs

Use AWS-managed encryption when sufficient.

Use customer-managed KMS keys when security, compliance, access-control, or lifecycle requirements justify them.

Do not introduce customer-managed KMS keys without a clear requirement.

---

## S3

Frontend buckets should remain private.

Do not enable public bucket access merely to serve frontend content.

CloudFront should access private S3 frontend content using Origin Access Control (OAC).

Do not use legacy Origin Access Identity (OAI) for new infrastructure when OAC is supported.

Block public access on private frontend buckets.

---

## CloudFront

Use HTTPS for viewer connections.

Redirect viewer HTTP to HTTPS.

For environments using the default `*.cloudfront.net` domain, use the CloudFront default viewer certificate.

When a custom domain is enabled, use an ACM certificate in `us-east-1` as required by CloudFront.

Keep origins private where supported.

For CloudFront VPC Origin, the application ALB should remain internal.

Dynamic API paths should not be cached unless explicitly designed and verified as safe to cache.

Do not hardcode AWS-managed CloudFront policy IDs when they can be resolved through Terraform data sources.

---

## Shield Standard

AWS Shield Standard automatically provides baseline DDoS protection for supported AWS services including CloudFront.

Shield Standard requires no separate Terraform resource.

Do not create a Terraform resource for Shield Standard.

Do not confuse AWS Shield Standard with CloudFront Origin Shield.

CloudFront Origin Shield is a separate caching capability and should only be enabled when justified by architecture, performance, or cost requirements.

---

## WAF

Attach AWS WAF to CloudFront when required by the environment.

WAF is optional for DEV unless explicitly enabled.

Evaluate WAF requirements separately for staging and production based on security, exposure, compliance, and cost requirements.

Use only rules justified by the application's security requirements.

Avoid unnecessary managed-rule groups or configurations that add cost without a clear security benefit.

---

## Logging and Detection

Use appropriate security, logging, and detection services including:

- CloudWatch
- CloudTrail
- GuardDuty
- AWS Config

CloudWatch log groups must define retention periods.

Logging and detection controls may differ by environment based on security, compliance, operational, and cost requirements.

Do not enable services or retain logs indefinitely without a defined requirement.

---

## Security Review

Check infrastructure changes for:

- unintended public exposure
- excessive IAM permissions
- unnecessary wildcard permissions
- unrestricted security groups
- public IP assignment to private workloads
- plaintext or hardcoded secrets
- missing encryption
- missing or indefinite log retention
- insecure S3 access
- unnecessary resources
- hardcoded AWS account-specific identifiers
- circular or unnecessary cross-module dependencies

Security improvements should preserve established architecture unless a change has a clear security, reliability, scalability, maintainability, compliance, cost, or product reason.

---

## Environment Guidance

### Development

Prefer the simplest secure and cost-conscious implementation.

For the current DEV architecture:

- use the default `*.cloudfront.net` domain
- use the CloudFront default viewer certificate
- keep the frontend S3 bucket private behind OAC
- keep the application ALB internal
- keep ECS tasks in private subnets without public IP addresses
- use CloudFront VPC Origin for private ALB access
- do not require Route 53 or a custom ACM certificate
- do not require WAF unless explicitly enabled
- rely on automatic AWS Shield Standard protection where supported

### Staging and Production

Do not create staging or production environments unless explicitly requested.

When those environments are introduced, evaluate additional controls separately, including:

- custom domains
- Route 53
- ACM certificates
- AWS WAF
- stronger monitoring and alerting
- expanded audit logging
- customer-managed KMS keys where justified
- backup and recovery requirements
- high-availability and disaster-recovery requirements
- environment-specific compliance controls

Do not assume DEV security or cost decisions automatically apply to staging or production.