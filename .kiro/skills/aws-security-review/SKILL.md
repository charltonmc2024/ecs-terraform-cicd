---
name: aws-security-review
description: Review the Erudition Solution development AWS infrastructure for least privilege, private networking, encryption, secrets handling, logging, and unintended public exposure.
---

# AWS Security Review Skill

## Purpose

Review Terraform and AWS architecture for security problems before deployment.

Current environment:

`envs/dev`

Security should remain practical and cost-conscious for development.

## Review Areas

Review:

1. IAM
2. Networking
3. Security groups
4. S3
5. CloudFront
6. ECS
7. DynamoDB
8. Secrets
9. Encryption
10. Logging
11. WAF
12. CI/CD credentials

## IAM

Check for least privilege.

Flag:

- AdministratorAccess
- unnecessary `*` actions
- unnecessary `*` resources
- long-lived IAM users
- embedded credentials

Prefer IAM roles.

Separate:

- ECS execution role
- ECS task role
- Jenkins role

where responsibilities differ.

## Networking

Expected application architecture:

Internet
   |
CloudFront
   |
VPC Origin
   |
Internal ALB
   |
ECS Fargate

ECS should run in private subnets.

ECS tasks should normally use:

`assign_public_ip = false`

## Security Groups

Prefer security-group references.

Expected relationship:

CloudFront/VPC Origin
        |
Internal ALB SG
        |
ECS SG

Flag unnecessary:

`0.0.0.0/0`

rules.

## S3

Frontend S3 bucket should remain private.

Check:

- public access block
- bucket policy
- encryption
- CloudFront Origin Access Control

Do not make the bucket public simply to make CloudFront work.

## CloudFront

Check:

- HTTPS
- ACM certificate
- HTTP-to-HTTPS redirect
- correct origins
- Origin Access Control
- VPC Origin configuration

AWS Shield Standard is automatically provided for supported services
such as CloudFront.

Do not create a Shield Standard Terraform resource.

## ECS

Check:

- private subnets
- no unnecessary public IP
- correct security group
- task execution role
- task role
- secrets injection
- CloudWatch logging

## DynamoDB

Check:

- encryption
- Point-in-Time Recovery when required
- access through IAM
- unnecessary public-style access patterns

## Secrets

Never allow secrets in:

- Git
- Terraform source
- Dockerfile
- Jenkinsfile
- committed tfvars

Use:

- Secrets Manager
- SSM Parameter Store
- Jenkins Credentials

## Encryption

Review encryption for:

- S3
- DynamoDB
- backups
- secrets
- logs where appropriate

Use KMS when requirements justify a customer-managed key.

## Logging

Check:

- CloudWatch log retention
- CloudTrail
- GuardDuty
- AWS Config

Avoid indefinite CloudWatch retention unless intentionally required.

## WAF

Review WAF configuration for CloudFront.

Keep rules appropriate for the development environment.

Avoid unnecessary paid rules or excessive complexity.

## Security Report

Classify findings as:

Critical
High
Medium
Low
Informational

For every issue explain:

- what was found
- why it matters
- affected Terraform resource
- recommended correction
- potential cost impact

Do not change architecture automatically for low-risk findings.