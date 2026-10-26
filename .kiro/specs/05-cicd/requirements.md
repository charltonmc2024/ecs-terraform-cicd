# Requirements Document

## Introduction

This spec covers the Jenkins CI/CD pipeline for the Erudition Solution development environment. Jenkins is
the mandated CI/CD platform for this project; AWS CodePipeline, GitHub Actions, and any other CI/CD platform
are out of scope and MUST NOT be introduced. The pipeline logic itself belongs in a repository-root
`Jenkinsfile`, not inside any Terraform module. No `Jenkinsfile` exists in the repository yet — this spec
defines the requirements the future `Jenkinsfile` MUST satisfy. This spec authors requirements only; it does
not create the `Jenkinsfile`, Terraform, a design, or tasks, and it performs no `terraform apply` or ECS
deployment.

The pipeline targets the development environment only. Its Terraform working directory is
`ecs-terraform/envs/dev/` (the Dev_Root), and its application source is the Next.js application at
`ecs-application/`. The pipeline consumes existing infrastructure interfaces rather than creating new ones:
the Backend_Module (spec 03-backend) already provisions the ECR repository (`${name_prefix}-app`, with
`scan_on_push = true` and MUTABLE tags in DEV), the ECS Fargate cluster/service/task-definition, the internal
ALB with a target-group health check on `var.health_check_path`, and autoscaling. The Dev_Root re-exports the
outputs the pipeline consumes: `ecr_repository_url`, `ecs_cluster_name`, `ecs_service_name`, and
`cloudfront_domain_name`.

Several ground-truth facts about the current repository drive these requirements and are stated up front
because they are unresolved or introduce prerequisites:

- **No application test runner exists.** The application `package.json`
  (name `erudition-solution-nextjs`) defines `dev`, `build`, `start`, and `lint` scripts, but there is **no
  `test` script and no test framework**. The pipeline requires an application test stage, so this is a
  tracked prerequisite (see Requirement 1 and the Cross-Module section).
- **The ECS task definition is currently fully Terraform-managed.** The Backend_Module sets the container
  image to `"${aws_ecr_repository.app.repository_url}:${var.image_tag}"`, the service pins
  `task_definition = aws_ecs_task_definition.app.arn` and `desired_count = var.desired_count`, `var.image_tag`
  defaults to `"latest"` in `envs/dev/terraform.tfvars`, and the service has **no** `lifecycle`
  `ignore_changes` and **no** `deployment_circuit_breaker`. This creates a task-definition ownership question
  between Jenkins and Terraform that MUST be resolved (see Requirement 9).
- **No first image exists.** ECS cannot start tasks without a pullable image, so first-deployment ordering is
  a prerequisite (see Requirement 10).
- **The Terraform remote state backend is bootstrap-owned.** DEV state uses an S3 backend configured at
  `init` time with the dev state key `ecs-dev/terraform.tfstate` and a DynamoDB lock table. The pipeline
  consumes this backend; it MUST NOT create or maintain separate local state (see Requirements 8 and 10).
- **CloudFront is the only public entry point.** The ALB is internal, ECS tasks are private with
  `assign_public_ip = false`, and public application verification MUST use the CloudFront domain
  (`cloudfront_domain_name`), never the internal ALB or ECS tasks directly.

## Glossary

- **Pipeline**: The Jenkins CI/CD pipeline defined by the repository-root `Jenkinsfile`
- **Jenkinsfile**: The repository-root pipeline definition file (not part of any Terraform module)
- **Dev_Root**: The Terraform root module and DEV working directory at `ecs-terraform/envs/dev/`
- **App_Source**: The Next.js application source at `ecs-application/`
- **App_Dockerfile**: The multi-stage Dockerfile at `ecs-application/Dockerfile` (node:20-alpine, Next.js
  standalone output, non-root `nextjs` user, `EXPOSE 3000`, `CMD ["node","server.js"]`)
- **Backend_Module**: The existing module at `ecs-terraform/modules/backend/` that provisions ECR, the
  internal ALB, and the ECS Fargate cluster/service/task-definition
- **App_Repository**: The ECR repository `${name_prefix}-app` created by the Backend_Module, exposed to the
  Pipeline via the Dev_Root output `ecr_repository_url`
- **ECS_Cluster / ECS_Service / Task_Definition**: The Fargate cluster, service, and task definition provided
  by the Backend_Module, referenced via `ecs_cluster_name` and `ecs_service_name`
- **Internal_ALB**: The internal Application Load Balancer that fronts the ECS service; not publicly reachable
- **CloudFront_Domain**: The default `*.cloudfront.net` domain exposed via the Dev_Root output
  `cloudfront_domain_name`, used as the public application verification entry point
- **Image_Tag**: The immutable Git commit SHA used to tag the built container image
- **Jenkins_Role**: The least-privilege IAM role (or equivalent credential mechanism) Jenkins uses to call
  AWS APIs
- **State_Backend**: The bootstrap-owned S3 remote-state backend plus DynamoDB lock table; DEV state key
  `ecs-dev/terraform.tfstate`
- **CICD_Module**: The Terraform module directory `ecs-terraform/modules/cicd/`, currently empty, which MAY
  provision infrastructure Jenkins needs (for example the Jenkins_Role) but MUST NOT contain the Pipeline
- **Required_Stage**: Any pipeline stage whose failure MUST stop dependent deployment stages (application
  tests, Terraform checks, Docker build, image scan, ECR push, ECS deploy, deployment verification)
- **Plan_Artifact**: The saved `terraform plan` output that a subsequent gated `terraform apply` consumes

## Requirements

### Requirement 1: Application Tests and Terraform Quality Checks

**User Story:** As a platform engineer, I want the Pipeline to run application tests, lint, build, and the
full Terraform quality suite for the DEV root, so that no unverified application code or malformed Terraform
proceeds toward deployment.

#### Acceptance Criteria

1. WHEN the Pipeline runs, THE Pipeline SHALL execute an application test stage, an application lint stage,
   and an application build stage against the App_Source.
2. WHEN the Pipeline runs Terraform checks, THE Pipeline SHALL execute
   `terraform fmt -check -recursive`, `terraform init`, `terraform validate`, and `terraform plan` for the
   Dev_Root.
3. IF any application test, lint, build, or Terraform check exits non-zero, THEN THE Pipeline SHALL fail and
   SHALL NOT continue to any dependent deployment stage.
4. IF no application `test` script or test framework is configured in the App_Source, THEN THE Pipeline SHALL
   fail the application test stage rather than silently passing, unless an explicit, documented no-tests gate
   is configured to permit continuation.
5. THE Pipeline SHALL record that the App_Source currently defines no `test` script and no test framework as
   a prerequisite that MUST be satisfied (a `test` script plus a test framework) before the application test
   stage can pass on real tests.
6. THE Pipeline SHALL run the Terraform quality suite against the Dev_Root only and SHALL NOT run it against
   any staging or production directory.

### Requirement 2: Manual Approval Gate Before Terraform Apply

**User Story:** As a platform engineer, I want a human approval step between a successful `terraform plan` and
`terraform apply`, so that infrastructure changes are applied intentionally and never automatically.

#### Acceptance Criteria

1. WHEN `terraform plan` for the Dev_Root succeeds, THE Pipeline SHALL NOT automatically run
   `terraform apply`.
2. WHEN an infrastructure change is to be applied, THE Pipeline SHALL require an explicit human approval step
   before `terraform apply` runs.
3. WHEN the human approval is granted, THE Pipeline SHALL run `terraform apply` against the same reviewed
   Plan_Artifact produced by the gated `terraform plan`, and SHALL NOT re-plan-and-apply a different plan.
4. THE Pipeline SHALL keep infrastructure planning and application deployment logically distinguishable so
   that an application release does not implicitly apply infrastructure changes.
5. IF the human approval is not granted, THEN THE Pipeline SHALL NOT run `terraform apply` and SHALL treat the
   infrastructure change as not applied.

### Requirement 3: Docker Image Build, Test, and Vulnerability Scan

**User Story:** As a platform engineer, I want the container image built, smoke-tested, and scanned for
vulnerabilities before any deployment, so that only a verified, acceptably secure image reaches ECR and ECS.

#### Acceptance Criteria

1. WHEN the required application and Terraform check stages have succeeded, THE Pipeline SHALL build the
   container image from the App_Dockerfile.
2. WHEN the image build succeeds, THE Pipeline SHALL run image-level tests or smoke checks against the built
   image before any push or deploy.
3. WHEN the image is built, THE Pipeline SHALL scan the image for vulnerabilities before any deploy.
4. IF the vulnerability scan reports findings that meet or exceed a defined severity threshold, THEN THE
   Pipeline SHALL fail and SHALL NOT push or deploy the image.
5. THE Pipeline SHALL record that the App_Repository already enables ECR `scan_on_push`, and SHALL record as
   an open decision whether an additional in-pipeline pre-push scan is required in addition to the ECR
   scan-on-push.
6. THE Pipeline SHALL record the vulnerability-scan failure severity threshold as an open decision to be
   finalized in design if it is not otherwise specified.

### Requirement 4: Push to ECR with an Immutable Git-SHA Tag

**User Story:** As a platform engineer, I want the image tagged with the Git commit SHA and pushed to the
existing ECR repository using role-based authentication, so that every deployment references an immutable
version and no static credentials or hardcoded registry identifiers exist.

#### Acceptance Criteria

1. WHEN the Pipeline pushes an image, THE Pipeline SHALL tag the image with the Git commit SHA as the
   immutable Image_Tag that the deployment relies on.
2. WHERE a `latest` tag is applied, THE Pipeline SHALL treat `latest` as an optional convenience tag only and
   SHALL NOT use `latest` as the version the ECS deployment relies on for version identification.
3. WHEN the Pipeline authenticates to ECR, THE Pipeline SHALL authenticate using the Jenkins_Role (IAM
   role-based credentials) and SHALL NOT use static long-lived AWS access keys.
4. WHEN the Pipeline determines the target registry, THE Pipeline SHALL resolve the App_Repository from the
   Dev_Root output `ecr_repository_url` and SHALL NOT hardcode the registry URL, account ID, or repository
   name.
5. IF the ECR push fails, THEN THE Pipeline SHALL fail and SHALL NOT proceed to ECS deployment.

### Requirement 5: ECS Fargate Deployment, Stability, and Health Verification

**User Story:** As a platform engineer, I want the Pipeline to deploy the immutable image to the existing ECS
service and confirm the service reaches a healthy steady state, so that only a verified running deployment is
accepted, without changing the private architecture.

#### Acceptance Criteria

1. WHEN the Pipeline deploys, THE Pipeline SHALL deploy the immutable Image_Tag to the ECS_Service using the
   existing architecture (Fargate, private subnets, `assign_public_ip = false`, internal ALB) and SHALL NOT
   make architectural changes to simplify deployment.
2. WHEN the Pipeline references ECS targets, THE Pipeline SHALL resolve the cluster and service from the
   Dev_Root outputs `ecs_cluster_name` and `ecs_service_name` and SHALL NOT hardcode cluster or service
   identifiers.
3. WHEN a deployment is initiated, THE Pipeline SHALL wait for the ECS_Service to reach a stable steady state.
4. WHEN verifying the deployment, THE Pipeline SHALL confirm the desired task count equals the running task
   count, SHALL detect failed tasks, and SHALL confirm ALB target health for the deployed tasks.
5. WHEN performing public application verification, THE Pipeline SHALL verify through the CloudFront_Domain
   (`cloudfront_domain_name`) and SHALL NOT expose or verify against the Internal_ALB or ECS tasks directly.
6. IF the ECS_Service does not reach a stable steady state, or running tasks do not equal desired tasks, or
   ALB target health is not achieved, THEN THE Pipeline SHALL treat the deployment as failed.

### Requirement 6: Failure Handling and Rollback

**User Story:** As a platform engineer, I want any failed required stage to stop the Pipeline and a failed
deployment to roll back to the last known-good version, so that failures are never suppressed and the running
service is not left broken.

#### Acceptance Criteria

1. IF any Required_Stage fails, THEN THE Pipeline SHALL stop and SHALL NOT continue to dependent deployment
   stages.
2. THE Pipeline SHALL NOT use failure-suppression patterns solely to force the Pipeline to appear successful.
3. IF a deployment is reported failed or unstable, THEN THE Pipeline SHALL roll back to the previous working
   ECS deployment (the previous task-definition revision or previous known-good image).
4. THE Pipeline SHALL log sufficient information to diagnose a failure without exposing secret values.
5. THE spec SHALL record that the ECS_Service currently has no `deployment_circuit_breaker`, and SHALL require
   the rollback mechanism to be defined explicitly as one of: (a) enabling the ECS deployment circuit breaker
   with rollback in the Backend_Module Terraform, or (b) a Jenkins-driven redeploy of the last known-good
   task-definition revision. The choice SHALL be recorded as a design decision.

### Requirement 7: Least-Privilege AWS Access and Secure Jenkins Credentials

**User Story:** As a platform engineer, I want Jenkins to use a least-privilege IAM role and secure credential
handling, so that no over-broad permissions or hardcoded secrets exist anywhere in the pipeline or source.

#### Acceptance Criteria

1. THE Pipeline SHALL authenticate to AWS using the Jenkins_Role (a least-privilege IAM role) and SHALL NOT
   attach `AdministratorAccess` to it.
2. THE Jenkins_Role permissions SHALL be scoped to exactly the actions the Pipeline needs: ECR push/pull for
   the App_Repository, ECS deploy and describe actions for the ECS_Service and cluster, read/write to the
   specific Terraform State_Backend bucket and the DynamoDB lock table, and read of the required Dev_Root
   outputs; the role SHALL NOT grant unnecessary wildcard permissions.
3. THE Pipeline SHALL NOT hardcode AWS credentials in the Jenkinsfile, Terraform configuration, the
   App_Dockerfile, or the application source.
4. WHERE a secret is required by the Pipeline, THE Pipeline SHALL obtain it from Jenkins Credentials or AWS
   Secrets Manager and SHALL NOT store the secret value in committed files.
5. THE Pipeline SHALL NOT expose credentials or secret values in pipeline logs.

### Requirement 8: Required Jenkins Tools, Connectivity, and Terraform Outputs

**User Story:** As a platform engineer, I want the required Jenkins tools, network connectivity, and consumed
Terraform outputs enumerated, so that the pipeline environment is provisioned correctly and consumes existing
interfaces rather than hardcoding values.

#### Acceptance Criteria

1. THE Pipeline SHALL require these tools available on its agent: Docker, Node.js and npm matching the
   App_Source runtime, Terraform (`~> 1.16`), and the AWS CLI.
2. THE Pipeline SHALL require network connectivity from its agent to ECR, ECS, the Terraform State_Backend
   S3 bucket, the DynamoDB lock table, and the CloudFront_Domain used for verification.
3. THE Pipeline SHALL consume the Dev_Root outputs `ecr_repository_url`, `ecs_cluster_name`,
   `ecs_service_name`, and `cloudfront_domain_name`, and SHALL NOT hardcode the values those outputs provide.
4. THE Pipeline SHALL use the bootstrap-owned State_Backend and SHALL NOT create or maintain separate local
   Terraform state.
5. WHERE the CICD_Module provides infrastructure Jenkins needs (for example the Jenkins_Role), THE
   CICD_Module MAY create that infrastructure but SHALL NOT contain the Pipeline definition; the Pipeline
   SHALL remain in the repository-root Jenkinsfile.
6. THE spec SHALL record that `ecs-terraform/modules/cicd/` is currently empty and SHALL record as an open
   decision whether the CICD_Module provisions the Jenkins_Role now or later.

### Requirement 9: Non-Conflicting Ownership of ECS Task Definitions and Image Updates

**User Story:** As a platform engineer, I want exactly one owner of the running image tag so that Jenkins
deployments and Terraform runs do not revert each other, so that deployments are deterministic and drift-free.

#### Acceptance Criteria

1. THE spec SHALL state the current conflict explicitly: the Task_Definition container image is
   Terraform-managed via `var.image_tag` (default `"latest"`), the ECS_Service pins
   `task_definition = aws_ecs_task_definition.app.arn`, and the service has no `lifecycle` `ignore_changes`,
   so a Jenkins-driven image update and a subsequent `terraform apply` would revert each other.
2. THE spec SHALL require a resolved ownership model in which exactly one owner controls the running image
   tag, presented as a design decision between: (a) Terraform owns the Task_Definition and Jenkins passes the
   Git-SHA Image_Tag into Terraform (via `var.image_tag`) on apply, or (b) Terraform provisions the baseline
   and adds `lifecycle { ignore_changes = [...] }` on the container image / task definition so Jenkins owns
   image rollouts via new task-definition revisions.
3. WHEN the chosen ownership model is applied, THE Pipeline and Terraform SHALL NOT both write the running
   image tag in a way that causes one to revert the other (no drift between the deployed image and the
   Terraform-tracked image).
4. THE spec SHALL require that the finalized ownership model be documented in design before implementation,
   and SHALL NOT leave the running image controlled by two owners simultaneously.

### Requirement 10: First-Deployment Prerequisites and Bootstrap Ordering

**User Story:** As a platform engineer, I want the first-image and remote-state prerequisites defined with
explicit ordering, so that the ECS service can start on its first deployment and Terraform runs against a
valid backend.

#### Acceptance Criteria

1. THE spec SHALL require that a first container image is available in the App_Repository before the
   ECS_Service attempts to start tasks, because ECS cannot start tasks without a pullable image.
2. IF the ECS_Service is pinned to an Image_Tag that does not yet exist in the App_Repository, THEN the
   spec SHALL treat that as a first-deployment failure condition that the documented bootstrap MUST prevent.
3. THE spec SHALL require a documented first-image bootstrap (for example an initial image build and push to
   the Git-SHA tag, or a seed/placeholder image) performed before or as part of the first `terraform apply`,
   and SHALL require the ordering between the first image push and the first apply to be explicit.
4. THE spec SHALL require that the Terraform remote State_Backend is bootstrapped (it is bootstrap-owned)
   before the Pipeline runs `terraform init` against the Dev_Root.
5. THE spec SHALL record the first-image bootstrap approach as an open decision to be finalized in design.

### Requirement 11: Platform, Scope, and Convention Constraints

**User Story:** As a platform engineer, I want the pipeline constrained to Jenkins and DEV with consistent
conventions, so that no alternate platform, environment, or hardcoded identifier is introduced.

#### Acceptance Criteria

1. THE Pipeline SHALL be defined for Jenkins and SHALL NOT introduce AWS CodePipeline, GitHub Actions, or any
   other CI/CD platform.
2. THE Pipeline SHALL target `ecs-terraform/envs/dev/` only and SHALL NOT define staging or production
   pipeline stages.
3. THE Pipeline SHALL reuse the existing Backend_Module infrastructure and Dev_Root outputs and SHALL NOT
   create duplicate application infrastructure.
4. THE Pipeline SHALL NOT hardcode AWS account IDs, ARNs, ECR URLs, cluster names, service names, or
   CloudFront identifiers; all such values SHALL derive from Dev_Root outputs, Jenkins Credentials, or
   established project interfaces.
5. THE Pipeline definition SHALL live in the repository-root Jenkinsfile and SHALL NOT be placed inside any
   Terraform module.

## Out of Scope

The following are explicitly out of scope for this spec and MUST NOT be implemented by the Pipeline: staging
and production pipelines and any staging/production pipeline stages; multi-account deployment; blue/green or
canary deployment strategies beyond the single chosen rollback model in Requirement 6 unless explicitly
specified; changing the application framework (the application remains Next.js); and observability and WAF
specifications (CloudWatch alarms/dashboards, SNS, WAF, GuardDuty, CloudTrail, AWS Config) that are owned by
the observability spec (06-observability). Authoring the `Jenkinsfile`, the Terraform for the CICD_Module,
the design, and the tasks is out of scope for this requirements document. Actually running `terraform apply`
or performing an ECS deployment is out of scope for this spec.

## Cross-Module Dependencies and Open Questions

These items were identified against the actual state of the repository and MUST be resolved in design before
implementation. They represent missing prerequisites and unresolved decisions, not resolved facts.

1. **No application test runner (missing prerequisite).** The App_Source `package.json`
   (`erudition-solution-nextjs`) defines only `dev`, `build`, `start`, and `lint` — there is no `test` script
   and no test framework. The Pipeline requires an application test stage; adding a `test` script plus a test
   framework is a prerequisite. Until it exists, the test stage MUST fail rather than silently pass, unless an
   explicit documented no-tests gate is chosen (see Requirement 1).
2. **Task-definition ownership model (unresolved decision).** The Task_Definition image is Terraform-managed
   via `var.image_tag` (default `"latest"`), the service pins
   `task_definition = aws_ecs_task_definition.app.arn`, and there is no `ignore_changes`. Design MUST choose
   between (a) Terraform-owns-tag with Jenkins passing the Git-SHA into `var.image_tag`, or
   (b) `lifecycle ignore_changes` on the container image / task definition so Jenkins owns image rollouts
   (see Requirement 9).
3. **Rollback mechanism (unresolved decision).** The ECS_Service has no `deployment_circuit_breaker`. Design
   MUST choose between enabling the ECS deployment circuit breaker with rollback in Terraform, or a
   Jenkins-driven redeploy of the last known-good task-definition revision (see Requirement 6).
4. **First-image bootstrap approach (unresolved decision).** No image exists in the App_Repository yet, and a
   service pinned to a non-existent tag will fail to start. Design MUST document how the first image is made
   available (initial build+push to the Git-SHA tag, or a seed/placeholder image) and the ordering relative
   to the first `terraform apply` (see Requirement 10).
5. **CICD_Module scope (unresolved decision).** `ecs-terraform/modules/cicd/` is currently empty. Design MUST
   decide whether the CICD_Module provisions the Jenkins_Role and other Jenkins infrastructure now or later;
   in all cases the Pipeline itself MUST remain in the repository-root Jenkinsfile (see Requirement 8).
6. **Vulnerability-scan failure threshold (unresolved decision).** The severity threshold at which the image
   scan fails the Pipeline is not specified, and whether an in-pipeline pre-push scan is required in addition
   to ECR `scan_on_push` is undecided (see Requirement 3).
7. **Jenkins agent/credential model (unresolved decision).** Whether Jenkins runs on an in-account EC2 agent
   assuming an instance/IAM role versus an external agent affects the IAM and credential model for the
   Jenkins_Role. Design MUST decide this because it changes how the least-privilege credentials in
   Requirement 7 are delivered.
