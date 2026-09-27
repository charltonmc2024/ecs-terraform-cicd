# AWS Security Standards

## Principle

Use least privilege and private-by-default architecture.

## IAM

Prefer IAM roles over IAM users.

Grant only permissions required by each workload.

Avoid:

- AdministratorAccess for workloads
- unnecessary wildcard permissions
- long-lived AWS credentials
- credentials stored in source code

Separate responsibilities where appropriate.

Examples:

- ECS execution role
- ECS task role
- Jenkins role

## Network Security

ECS workloads run in private subnets.

ECS tasks should not receive public IP addresses.

The application ALB should remain internal when used through
CloudFront VPC Origin.

Prefer security-group-to-security-group rules.

Avoid:

`0.0.0.0/0`

unless public access is intentionally required.

## Secrets

Never commit secrets to Git.

Never hardcode secrets inside:

- Terraform
- Dockerfiles
- Jenkinsfile
- application source
- committed tfvars

Use:

- AWS Secrets Manager
- AWS Systems Manager Parameter Store
- Jenkins Credentials

Mark Terraform values as sensitive where appropriate.

## Encryption

Enable encryption where appropriate for:

- S3
- DynamoDB
- backups
- secrets
- CloudWatch Logs

Use AWS-managed encryption when sufficient.

Use customer-managed KMS keys where requirements justify them.

## S3

Frontend buckets should remain private.

Do not enable public bucket access merely to serve the frontend.

CloudFront should access private S3 content using Origin Access Control.

## CloudFront

Use HTTPS.

Use ACM certificates.

Redirect HTTP to HTTPS where appropriate.

## Shield Standard

AWS Shield Standard automatically provides baseline DDoS protection
for supported services including CloudFront.

Shield Standard requires no separate Terraform resource.

Do not confuse AWS Shield Standard with CloudFront Origin Shield.

## WAF

Attach AWS WAF to CloudFront when enabled.

Keep WAF rules appropriate for the development environment and
cost-conscious.

## Logging and Detection

Use appropriate services including:

- CloudWatch
- CloudTrail
- GuardDuty
- AWS Config

CloudWatch log groups must define retention periods.

## Security Review

Check infrastructure changes for:

- unintended public exposure
- excessive IAM permissions
- unrestricted security groups
- plaintext secrets
- missing encryption
- missing logging
- unnecessary resources