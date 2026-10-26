# Implementation Plan: 05-cicd

## Overview

This plan authors the Jenkins CI/CD Pipeline for the Erudition Solution development environment plus the
small amount of Terraform-support work the Pipeline depends on. The Pipeline itself lives in a single
repository-root `Jenkinsfile`; Jenkins is the mandated platform and no other CI/CD system (AWS CodePipeline,
GitHub Actions, or otherwise) is introduced. The Pipeline targets the Dev_Root at `ecs-terraform/envs/dev/`
only — there are no staging or production stages — and its application source is the Next.js App_Source at
`ecs-application/`. The Pipeline creates no application infrastructure: it reuses the existing 03-backend
module (ECR `${name_prefix}-app` with `scan_on_push = true`, the internal ALB + IP target group, the ECS
Fargate cluster/service/task-definition, and autoscaling) and reads `ecr_repository_url`, `ecs_cluster_name`,
`ecs_service_name`, and `cloudfront_domain_name` at runtime via `terraform output`. No account ID, ARN, ECR
URL, cluster/service name, or CloudFront identifier is hardcoded.

Work is ordered so that prerequisites and Terraform-support come before pipeline authoring: first the
tracked prerequisites (application test setup, the additive 03-backend circuit-breaker change, the
bootstrap-owned remote state confirmation, and the Jenkins agent/credential decision); then the
least-privilege Jenkins_Role in the currently-empty `modules/cicd` wired from `envs/dev`; then the documented
first-image bootstrap ordering; then the repository-root `Jenkinsfile` stages authored incrementally
(skeleton → checkout → app checks → Terraform checks → approval gate → gated apply → Docker build/smoke →
scan → ECR push → ECS deploy → steady-state/health → CloudFront verification → failure handling/rollback →
secure secrets); and finally verification and an operator checkpoint.

The chosen design decisions are reflected throughout: **Terraform owns the running image tag** (Jenkins
passes the Git-SHA `var.image_tag` into the gated `terraform apply`, so exactly one owner writes the tag);
**rollback** uses the ECS `deployment_circuit_breaker { enable = true, rollback = true }` as primary with a
Jenkins previous-tag `terraform apply` fallback; and the **first-image bootstrap** creates ECR ahead of the
service (targeted apply or `desired_count = 0`) so the service is never pinned to a missing tag.

This is CI/CD pipeline + Terraform-support work, not a pure input/output function, so property-based testing
does not apply and there are NO executable property-based tests. Verification is by Jenkinsfile lint /
pipeline replay, `terraform fmt`/`validate`/`plan` (never `apply`), and IAM policy review. Authoring these
tasks performs NO `terraform apply`, NO image build/push, and NO ECS deployment — every apply/push/deploy is
gated behind explicit operator action.

## Tasks

- [ ] 1. Satisfy tracked prerequisites before authoring the Pipeline
  - [ ] 1.1 Add an application test setup to the App_Source
    - Add a `test` script plus a test framework (for example Jest or Vitest) to
      `ecs-application/package.json`, with at least one passing smoke test under the App_Source
    - Acceptance: `npm test` exits 0 with >= 1 executed test; wire it so the future pipeline test stage runs
      real tests, not a silent pass
    - Document that until this exists the test stage MUST fail (no silent pass) OR run behind an explicit,
      logged, human-set no-tests gate; the DEV default is to require the test setup rather than open the gate
    - Do NOT change the application framework (remains Next.js); add no unrelated scripts
    - _Requirements: 1.1, 1.4, 1.5_

  - [ ] 1.2 Add the ECS deployment circuit breaker with rollback to the 03-backend ECS service
    - In `ecs-terraform/modules/backend/ecs.tf`, add `deployment_circuit_breaker { enable = true, rollback = true }`
      to the `aws_ecs_service` as a small additive cross-module change (primary automatic rollback per design)
    - Note this change touches 03-backend and MUST be planned/validated, not applied, in this spec
    - Acceptance: `terraform fmt`/`validate` clean; `terraform plan` shows only the additive circuit-breaker
      change (0 destroy) and no other backend drift
    - _Requirements: 6.3, 6.5_

  - [ ] 1.3 Confirm the bootstrap-owned remote State_Backend is available to Jenkins
    - Confirm the S3 state bucket + DynamoDB lock table exist (bootstrap-owned) and record the dev state key
      `ecs-dev/terraform.tfstate` and the `-backend-config` values the Pipeline will pass to `terraform init`
    - Acceptance: documented backend-config inputs for the Pipeline; the Pipeline uses this backend and keeps
      NO separate local Terraform state
    - _Requirements: 8.4, 10.4_

  - [ ] 1.4 Decide and document the Jenkins agent / credential model
    - Record whether Jenkins runs on an in-account EC2 agent assuming an instance/assumed IAM role versus an
      external agent, since this drives how the least-privilege Jenkins_Role credentials are delivered
    - Acceptance: a written decision (recommended: in-account agent with a role) that the Jenkins_Role and
      Jenkinsfile auth stages consume; no static long-lived AWS keys implied
    - _Requirements: 7.1, 8.1_

- [ ] 2. Implement the least-privilege Jenkins_Role in the CICD_Module (Terraform-support, not the Pipeline)
  - [ ] 2.1 Create the Jenkins_Role and scoped policy in `modules/cicd`
    - In the currently-empty `ecs-terraform/modules/cicd/`, define an `aws_iam_role` (Jenkins_Role) with the
      trust policy matching the agent/credential decision from task 1.4, plus a scoped policy granting exactly:
      ECR push/pull for the App_Repository; ECS describe/update/register for the Dev cluster + service;
      read/write to the specific State_Backend S3 bucket and the DynamoDB lock table; and read of the required
      Dev_Root outputs
    - Attach NO `AdministratorAccess`; grant NO unnecessary wildcard permissions and NO `Resource: "*"`
    - Reference resource ARNs from variables/module inputs/outputs — no hardcoded account IDs, ARNs, bucket
      names, or table names
    - Record the design decision of whether the CICD_Module provisions the Jenkins_Role now or later; the
      Pipeline definition MUST NOT live in this module
    - Acceptance: `terraform fmt`/`validate` clean; IAM policy review shows least privilege
    - _Requirements: 7.1, 7.2, 8.5, 8.6, 11.4_

  - [ ] 2.2 Wire the CICD_Module from the Dev_Root
    - Add a `module "cicd"` block in `envs/dev/main.tf` passing the required inputs (state bucket, lock table,
      ECR/cluster/service references) from existing module outputs / Dev_Root values — never literals
    - Preserve the existing `module "network"`, `module "data"`, and `module "backend"` blocks
    - Acceptance: `terraform fmt`/`validate` clean; `terraform plan` shows only the Jenkins_Role/policy
      additions (0 destroy)
    - _Requirements: 8.5, 8.6, 11.4_

- [ ] 3. Document the first-image bootstrap procedure (ordered runbook; no execution)
  - [ ] 3.1 Write the ordered first-image bootstrap runbook
    - Define the ordering: (1) State_Backend exists → (2) create ECR first via targeted apply (or apply the
      service with `desired_count = 0`) → (3) Jenkins builds + pushes the first image to the Git-SHA tag →
      (4) create/scale the service with `var.image_tag=<git-sha>` so it starts against an existing image
    - Acceptance: a written runbook that makes a "service pinned to a missing tag" condition unreachable;
      no `terraform apply`, image build, or push is performed by authoring this task
    - Keep the single immutable Git-SHA tagging scheme from the first deployment (no reliance on a
      `latest`-only placeholder for version identification)
    - _Requirements: 10.1, 10.2, 10.3, 10.5_

- [ ] 4. Author the repository-root Jenkinsfile Pipeline stages
  - [ ] 4.1 Create the Jenkinsfile skeleton, agent, tools, auth, and parameters
    - Create `Jenkinsfile` at the repository root (NOT inside any Terraform module)
    - Declare the agent/tools: Docker, Node.js and npm matching the App_Source runtime, Terraform (`~> 1.16`),
      and the AWS CLI; authenticate to AWS via the Jenkins_Role (role-based), never static keys
    - Declare parameters including the Git commit SHA used as the Image_Tag; resolve `ecr_repository_url`,
      `ecs_cluster_name`, `ecs_service_name`, and `cloudfront_domain_name` via `terraform output` — no
      hardcoded identifiers
    - _Requirements: 8.1, 8.2, 8.3, 4.4, 11.4, 11.5_

  - [ ] 4.2 Add the Checkout stage
    - Fetch App_Source, Dev_Root, and `Jenkinsfile` at the commit under test; capture the Git commit SHA as
      the immutable Image_Tag for later stages
    - Acceptance: `git_commit_sha` captured; checkout error stops the Pipeline
    - _Requirements: 4.1, 11.5_

  - [ ] 4.3 Add the application test / lint / build stage
    - Run the application test, lint, and build stages against the App_Source (`npm ci`, `npm test`,
      `npm run lint`, `npm run build`)
    - Acceptance: any non-zero exit stops the Pipeline; a missing `test` script fails the stage (no silent
      pass) unless the explicit documented no-tests gate from task 1.1 is set
    - _Requirements: 1.1, 1.3, 1.4_

  - [ ] 4.4 Add the Terraform quality stage (Dev_Root only)
    - Run `terraform fmt -check -recursive`, `terraform init` with the bootstrap `-backend-config`,
      `terraform validate`, and `terraform plan -out=tfplan` against `ecs-terraform/envs/dev/` only
    - Acceptance: any non-zero exit stops the Pipeline; the `tfplan` Plan_Artifact is produced; the suite
      runs against no staging/production directory
    - _Requirements: 1.2, 1.3, 1.6, 8.4_

  - [ ] 4.5 Add the manual approval gate before apply
    - Add a Jenkins `input` step that requires an explicit human approval after a successful `terraform plan`
      and before any `terraform apply`
    - Acceptance: apply never runs automatically on plan success; if approval is not granted, no apply runs
      and the infrastructure change is treated as not applied
    - _Requirements: 2.1, 2.2, 2.5_

  - [ ] 4.6 Add the gated terraform apply supplying the Git-SHA image tag
    - After approval, run `terraform apply tfplan` against the same reviewed Plan_Artifact, supplying
      `var.image_tag=<git-sha>` (Terraform-owns-tag ownership model) so exactly one owner writes the running
      tag
    - Acceptance: the apply consumes the reviewed `tfplan` (no re-plan/different plan); infrastructure
      planning and application deployment stay logically distinguishable
    - _Requirements: 2.3, 2.4, 9.2, 9.3_

  - [ ] 4.7 Add the Docker build + image smoke test stage
    - Build the container image from the App_Dockerfile, then run an image-level smoke check (start the
      container and probe the health path) before any push or deploy
    - Acceptance: build or smoke failure stops the Pipeline before any push
    - _Requirements: 3.1, 3.2_

  - [ ] 4.8 Add the vulnerability scan stage with a defined threshold
    - Scan the built image before any deploy; fail the Pipeline when findings meet or exceed the defined
      severity threshold; record that the App_Repository already enables ECR `scan_on_push` and whether an
      additional in-pipeline pre-push scan is used
    - Acceptance: findings at/above threshold stop the Pipeline with no push and no deploy
    - _Requirements: 3.3, 3.4, 3.5, 3.6_

  - [ ] 4.9 Add the ECR login + tag + push stage
    - Authenticate to ECR using the Jenkins_Role, tag the image with the Git commit SHA, and push to the
      repository resolved from `ecr_repository_url`; treat any `latest` tag as convenience only
    - Acceptance: no static AWS keys; no hardcoded registry URL/account/repo; ECR push failure stops the
      Pipeline before ECS deploy
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5_

  - [ ] 4.10 Add the ECS deploy stage (via the gated apply)
    - Deploy the Git-SHA image to the ECS service through the gated `terraform apply` (which registers the new
      task-definition revision and updates the service); resolve cluster/service from `ecs_cluster_name` /
      `ecs_service_name`; run no competing `update-service` that also writes the tag
    - Acceptance: the service keeps Fargate, private subnets, `assign_public_ip = false`, and the internal
      ALB unchanged (no architectural change to simplify deployment)
    - _Requirements: 5.1, 5.2, 9.3, 11.3_

  - [ ] 4.11 Add the steady-state wait and health verification stage
    - Wait for the ECS service to reach a stable steady state; confirm desired task count equals running task
      count; detect failed tasks; confirm ALB target health for the deployed tasks
    - Acceptance: if steady state is not reached, running != desired, or target health is not achieved, the
      deployment is treated as failed (and triggers rollback in task 4.13)
    - _Requirements: 5.3, 5.4, 5.6_

  - [ ] 4.12 Add the public verification stage via CloudFront
    - Issue an HTTPS request to `cloudfront_domain_name` and assert an expected healthy response
    - Acceptance: verification uses the CloudFront domain only; the internal ALB and ECS tasks are never
      targeted directly; verification failure triggers rollback
    - _Requirements: 5.5_

  - [ ] 4.13 Add failure handling and rollback
    - On any Required_Stage failure, stop the Pipeline and block dependent deployment stages; on a failed or
      unstable deployment, roll back via the ECS deployment circuit breaker (primary) and, if needed, a
      Jenkins fallback `terraform apply` with the previous known-good `var.image_tag` (single-owner rule
      preserved)
    - Acceptance: no failure-suppression patterns; logs carry enough diagnostic context without exposing
      secret values
    - _Requirements: 6.1, 6.2, 6.3, 6.4_

  - [ ] 4.14 Add secure secret and credential handling across stages
    - Ensure no AWS credentials are hardcoded in the Jenkinsfile, Terraform, App_Dockerfile, or application
      source; obtain any required secret from Jenkins Credentials or AWS Secrets Manager at runtime; never
      echo secret values to logs
    - Acceptance: no secret value in committed files; no secret value in pipeline logs
    - _Requirements: 7.3, 7.4, 7.5_

- [ ] 5. Verification (no apply, no push, no deploy)
  - [ ]* 5.1 Jenkinsfile lint / pipeline replay
    - Run Jenkins declarative lint / pipeline replay to validate `Jenkinsfile` syntax, the stage graph, the
      required-stage gating, and that the manual approval gate precedes any apply
    - _Requirements: 1.3, 6.1_

  - [ ]* 5.2 Terraform fmt / validate for the changed Terraform
    - Run `terraform fmt -check -recursive` and `terraform validate` for `envs/dev`, `modules/cicd`, and the
      03-backend circuit-breaker change; perform no `terraform apply`
    - _Requirements: 1.2_

  - [ ]* 5.3 IAM least-privilege review of the Jenkins_Role
    - Review the Jenkins_Role policy: no `AdministratorAccess`, no wildcard/`Resource: "*"`, and scoping
      limited to the ECR, ECS, S3 state bucket, DynamoDB lock, and output-read actions the Pipeline needs
    - _Requirements: 7.1, 7.2_

  - [ ]* 5.4 Map each Correctness Property (1-17) to a concrete check
    - For each design property, record the verifying check: Jenkinsfile lint/replay (Properties 1-5, 16, 17),
      IAM policy review (Property 13), `terraform plan` / config review (Properties 7, 8, 11, 14, 15), and
      deploy-time checks (Properties 9, 10, 12); note that runtime properties (steady state, health,
      CloudFront reachability, rollback) are only fully verified at deploy time, not by lint/plan
    - _Requirements: 5.3, 5.4, 5.5, 6.3_

- [ ] 6. Final checkpoint - operator review before any apply/deploy
  - Present the Terraform plan(s) (Dev_Root + `modules/cicd` + the 03-backend circuit-breaker change), the
    authored `Jenkinsfile`, and the prerequisite/decision list (test framework, vulnerability threshold,
    CICD_Module scope, agent/role delivery, first-image seeding). Applying, pushing images, and deploying are
    all gated on explicit operator confirmation — do NOT auto-apply, do NOT push images, do NOT deploy. Ask
    the user before any `terraform apply`, image push, or ECS deployment.

## Notes

- This is CI/CD pipeline + Terraform-support work, not a pure input/output function, so property-based
  testing does not apply and there are NO executable property-based tests. Verification is via Jenkinsfile
  lint / pipeline replay, `terraform fmt`/`validate`/`plan`, and IAM policy review.
- Authoring these tasks performs NO `terraform apply`, NO image build/push, and NO ECS deployment. Every
  apply/push/deploy is gated behind explicit operator action (task 6).
- Scope is DEV / `ecs-terraform/envs/dev/` only; no staging or production pipeline stages are defined.
- The Pipeline reuses the existing 03-backend module and Dev_Root outputs (`ecr_repository_url`,
  `ecs_cluster_name`, `ecs_service_name`, `cloudfront_domain_name`) read via `terraform output`. No account
  IDs, ARNs, ECR URLs, cluster/service names, or CloudFront identifiers are hardcoded.
- Jenkins is the only CI/CD platform; the Pipeline lives in the repository-root `Jenkinsfile`, never inside a
  Terraform module. The CICD_Module may provision only the Jenkins_Role and Jenkins-support infrastructure.
- Ownership model: Terraform owns the running image tag; Jenkins passes the Git-SHA `var.image_tag` into the
  gated apply so exactly one owner writes the tag (no drift).
- Rollback: ECS `deployment_circuit_breaker { enable = true, rollback = true }` is primary; a Jenkins
  previous-tag `terraform apply` is the fallback, both converging on the last known-good revision.
- First-image bootstrap: ECR is created ahead of the service (targeted apply or `desired_count = 0`), then
  Jenkins pushes the first Git-SHA image, then the service is created/scaled on that tag — so the service is
  never pinned to a missing tag.
- The 03-backend circuit-breaker change (task 1.2) is a small additive cross-module change; it is
  planned/validated here but NOT applied.
- Tasks marked with `*` are optional verification sub-tasks and can be skipped for a faster path; core
  authoring tasks are never optional.

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "1.2", "1.3", "1.4"] },
    { "id": 1, "tasks": ["2.1"] },
    { "id": 2, "tasks": ["2.2", "3.1"] },
    { "id": 3, "tasks": ["4.1"] },
    { "id": 4, "tasks": ["4.2"] },
    { "id": 5, "tasks": ["4.3", "4.4"] },
    { "id": 6, "tasks": ["4.5"] },
    { "id": 7, "tasks": ["4.6"] },
    { "id": 8, "tasks": ["4.7"] },
    { "id": 9, "tasks": ["4.8"] },
    { "id": 10, "tasks": ["4.9"] },
    { "id": 11, "tasks": ["4.10"] },
    { "id": 12, "tasks": ["4.11"] },
    { "id": 13, "tasks": ["4.12"] },
    { "id": 14, "tasks": ["4.13", "4.14"] },
    { "id": 15, "tasks": ["5.1", "5.2", "5.3", "5.4"] },
    { "id": 16, "tasks": ["6"] }
  ]
}
```

## Phase 1 Progress (CI-only, no AWS actions)

A repository-root `Jenkinsfile` has been authored covering **Phase 1 only**: Checkout,
Application checks (test-gate/lint/build), backend-disabled Terraform checks
(`terraform fmt -check -recursive`, `terraform init -backend=false`, `terraform validate`),
and Docker build. Phase 1 performs NO bootstrap apply, NO remote-state access, NO
`terraform plan`/apply against real state, NO ECR push, NO ECS deploy, and NO CloudFront
verification.

Relative to the task list, Phase 1 partially implements:

- Task 4.1 (skeleton/agent/tools/parameters) — Phase 1 subset: agent + the `ALLOW_NO_TESTS`
  gate parameter. AWS auth / `terraform output` identifier resolution are deferred to later phases.
- Task 4.2 (Checkout) — implemented; captures `GIT_COMMIT_SHA` as the future immutable Image_Tag.
- Task 4.3 (app test/lint/build) — implemented; the missing-test-framework case fails the stage
  (no silent pass) unless the documented `ALLOW_NO_TESTS` gate is opened (R1.4/R1.5).
- Task 4.4 (Terraform quality) — Phase 1 uses `terraform init -backend=false` (no remote state)
  and runs fmt + validate only. The gated `terraform plan -out=tfplan` against real state is a
  later phase.
- Task 4.7 (Docker build + smoke) — Phase 1 implements the Docker BUILD only; the image smoke
  test, scan, push, and deploy are later phases.

Local verification of the underlying Phase 1 commands (run outside Jenkins): `terraform fmt
-check -recursive` clean; `terraform init -backend=false` + `terraform validate` succeed;
`npm run lint` clean; `npm run build` succeeds (Next.js standalone output). The declarative
pipeline lint and the Docker build stage require a configured Jenkins agent with Docker and
were NOT executed here (Docker is unavailable in this WSL environment).

These task checkboxes are intentionally left unchecked because each task's full acceptance
criteria span later phases; this note records the Phase 1 subset that is complete.
