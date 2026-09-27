---
name: jenkins-pipeline
description: Build and maintain the Jenkins CI/CD pipeline for Terraform validation, Next.js testing, Docker builds, Amazon ECR, and ECS Fargate deployment to the development environment.
---

# Jenkins Pipeline Skill

## Purpose

Build and maintain CI/CD for the Erudition Solution development environment.

Current deployment target:

`ecs-terraform/envs/dev`

Do not create staging or production pipelines unless explicitly requested.

## Pipeline Definition

The primary pipeline belongs in:

`Jenkinsfile`

at the repository root.

## Pipeline Architecture

Git
 |
Jenkins
 |
+-- Checkout
 |
+-- Application Test
 |
+-- Terraform Validation
 |
+-- Docker Build
 |
+-- ECR Push
 |
+-- ECS Deploy
 |
+-- Deployment Verification

## Application Stage

For the Next.js application:

1. Install dependencies.
2. Run linting where configured.
3. Run tests where configured.
4. Build the application.
5. Fail the pipeline if required checks fail.

Do not invent test commands that are not supported by `package.json`.

Inspect the application configuration first.

## Terraform Stage

Terraform working directory:

`ecs-terraform/envs/dev`

Run:

`terraform fmt -check -recursive`

`terraform init`

`terraform validate`

`terraform plan`

Do not continue infrastructure deployment when validation fails.

## Docker Build

Build the application Docker image using the repository Dockerfile.

Use immutable image tags.

Preferred:

- Git commit SHA
- Jenkins build number

Avoid depending only on:

`latest`

## ECR

Authenticate Jenkins securely to Amazon ECR.

Pipeline:

Docker build
   |
Docker tag
   |
ECR authentication
   |
Docker push

Do not hardcode ECR repository URLs if they can be obtained from
Terraform outputs or environment configuration.

## ECS Deployment

Deploy the intended image version to ECS Fargate.

The deployment should target the development ECS service.

Do not deploy an ambiguous `latest` image when an immutable image
identifier is available.

## Deployment Verification

After deployment:

- verify ECS service stability
- verify expected task count
- detect failed task startup
- detect failed health checks

A failed deployment should fail the pipeline.

## Credentials

Never put AWS access keys directly inside:

`Jenkinsfile`

Prefer:

1. IAM role
2. approved Jenkins credential mechanism
3. Secrets Manager where appropriate

Do not print secrets into Jenkins logs.

## Terraform Apply

Do not automatically introduce unattended infrastructure apply behavior.

Terraform workflow should clearly distinguish:

validation/plan

from:

apply

Infrastructure changes should have an intentional approval/deployment
mechanism.

## Failure Handling

These should stop the relevant pipeline:

- application test failure
- Terraform formatting failure
- Terraform validation failure
- Terraform planning failure
- Docker build failure
- ECR push failure
- ECS deployment failure
- ECS health check failure

Do not hide failures using unconditional success handling.

## Current Scope

The pipeline currently supports DEV only.

Do not add:

- staging deployment
- production deployment
- CodePipeline
- duplicate CI/CD platforms

unless explicitly requested.