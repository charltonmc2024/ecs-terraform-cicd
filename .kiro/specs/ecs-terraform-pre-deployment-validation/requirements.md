# Requirements Document

## Introduction

ECS Terraform Pre-Deployment Validation defines a read-only validation effort for the DEV environment of the Erudition Solution (AWS us-east-1, Terraform root `ecs-terraform/envs/dev/`). The DEV stack has not been applied. A saved plan (`tfplan-dev`) reports 51 to add, 0 to change, 0 to destroy; its currency relative to the current sources is verified by the checks, not assumed.

The effort inspects the existing Terraform configuration and saved plan, produces a structured validation checklist, classifies each check as pre-deployment or post-deployment and assigns it to one of three check groups (A: pre-deployment infrastructure, B: post-deployment infrastructure, C: application integration and CI/CD readiness), identifies mismatches and blockers, estimates recurring cost, and records every result as PASS, FAIL, BLOCKED, or NOT TESTED with evidence. It never changes infrastructure, Terraform files, or Jenkins pipelines, and it proposes fixes only for user approval.

Readiness is judged at two levels. Bootstrap Readiness (the immediate goal) means DEV infrastructure can be provisioned safely with ECS `desired_count = 0`. Application Deployment Readiness means the LMS application can run end to end. Known bootstrap limitations (landing-page image, empty S3 frontend, unpopulated Atlas cluster) affect Application Deployment Readiness but not Bootstrap Readiness.

Baseline facts observed during repository inspection (to be re-verified by the checks, not assumed as PASS):

- Architecture: network, backend, edge modules, plus observability and security modules; the `cicd` module directory is empty.
- ECS: `desired_count = 0`, autoscaling `min_capacity = 0`, `max_capacity = 2` (module default), image tag `sha-a454df4` (matches Git HEAD `a454df4`), `container_port = 3000`, `health_check_path = "/"`.
- Edge: private S3 bucket with OAC, CloudFront VPC Origin to internal ALB, `default_root_object = "index.html"`, ordered behaviors `/api/*` and `/v1/*`.
- Data: MongoDB Atlas M0 (external, currently empty); `app_secret_arn` and `staff_admin_secret_arn` reference the same Secrets Manager secret.
- Uncommitted change: `modules/edge/cloudfront.tf` (adds the `/v1/*` behavior); whether the Saved_Plan reflects it is verified from the git diff and plan content.
- ECR: a repository and image tag `sha-a454df4` reportedly already exist in AWS; their existence, state management, and treatment in the Saved_Plan are verified, not assumed.
- No `Jenkinsfile` is tracked in this repository, although Jenkins reportedly built and pushed the image.
- The ECR image is reported to be a Next.js landing page on port 3000, not the production LMS FastAPI API (a known bootstrap limitation).
- `tfplan-dev`, `tfplan-dev.json`, and `tfplan-dev-formatted.json` exist locally and are ignored by `.gitignore` (`tfplan-*`).

## Glossary

- **Validation_Suite**: The complete set of read-only checks defined by this specification.
- **Validator**: The agent or operator executing the Validation_Suite.
- **Dev_Root**: The Terraform root at `ecs-terraform/envs/dev/`.
- **Saved_Plan**: The binary plan file `ecs-terraform/envs/dev/tfplan-dev` and its JSON renderings.
- **Check**: A single test with an identifier, category, phase, Check_Group, method, expected result, and recorded status.
- **Bootstrap_Readiness**: The state in which DEV infrastructure can be safely provisioned with ECS `desired_count = 0`.
- **Application_Deployment_Readiness**: The state in which the LMS_API runs end to end on the provisioned infrastructure.
- **Readiness_Level**: Either Bootstrap_Readiness or Application_Deployment_Readiness.
- **Check_Group**: Exactly one of Group A, Group B, or Group C.
- **Group_A**: Pre-deployment infrastructure checks (Pre_Deployment_Check on infrastructure).
- **Group_B**: Post-deployment infrastructure verification (Post_Deployment_Check on infrastructure).
- **Group_C**: Application integration and CI/CD readiness tests; NOT TESTED or BLOCKED for application-dependent items until the application image and data exist.
- **Known_Limitation**: A bootstrap condition accepted in advance: the Landing_Page_Image, the empty S3 frontend, and the unpopulated Atlas cluster.
- **Blocks_Field**: A Finding field naming the Readiness_Level, phase, or specific acceptance criterion the Finding prevents.
- **Pre_Deployment_Check**: A Check completable from source files, the Saved_Plan, or read-only AWS/Git queries without deployed resources.
- **Post_Deployment_Check**: A Check requiring deployed AWS resources; recorded as NOT TESTED or BLOCKED before apply.
- **Status**: One of PASS, FAIL, BLOCKED, or NOT TESTED.
- **PASS**: The Check ran and its expected result was met, supported by recorded Evidence.
- **FAIL**: The Check ran and its expected result was not met.
- **BLOCKED**: The Check cannot run because a prerequisite is missing or failing.
- **NOT TESTED**: The Check has not been run.
- **Evidence**: A command with its redacted output, a file path with line reference, or a plan-derived value that supports a Status.
- **Finding**: A configuration mismatch, risk, or deployment blocker discovered by a Check, carrying a Blocks_Field and a severity per Readiness_Level.
- **Blocker**: A Finding that prevents a safe or functional deployment at a given Readiness_Level; severity is evaluated per Readiness_Level.
- **Readiness_Report**: The final deployment-readiness document summarizing all Checks (grouped A/B/C), Findings, cost, and two verdicts, one per Readiness_Level.
- **Recommendation**: A proposed action or fix issued by the Validator, always pending explicit user approval.
- **Read_Only_Command**: A command that does not create, modify, or delete AWS resources, Terraform state, Terraform files, or Jenkins configuration.
- **Atlas**: MongoDB Atlas, the external managed database (M0 cluster `ECSCluster`).
- **LMS_API**: The production FastAPI application (`eruditiontx-services-mvp`).
- **Landing_Page_Image**: The current ECR image, a Next.js landing page on port 3000.

## Requirements

### Requirement 1: Repository Inspection Before Recommendations

**User Story:** As a platform engineer, I want the existing repository inspected first, so that every recommendation is grounded in the current configuration.

#### Acceptance Criteria

1. WHEN the Validation_Suite starts, THE Validator SHALL read every `.tf` and `.tfvars` file in the Dev_Root, every `.tf` file in every module under `ecs-terraform/modules/`, every file under `.kiro/steering/`, and the `requirements.md`, `design.md`, and `tasks.md` files of specs 01 through 08 before recording the first Finding.
2. IF any file or directory in criterion 1 cannot be read, THEN THE Validator SHALL record a Finding naming the unreadable path and the reason, and SHALL continue inspecting the remaining files.
3. WHEN recording a Finding derived from source, THE Validator SHALL include as Evidence the file path and the line number or Terraform resource address, so that a reviewer can locate the source in one lookup.
4. IF a file expected by the user description is not found, THEN THE Validator SHALL record a Finding naming the missing file and listing each directory searched.
5. THE Validator SHALL treat Terraform files outside `ecs-terraform/modules/` and `ecs-terraform/envs/dev/` as reference-only, SHALL NOT cite them as implementation source for any Finding, and SHALL NOT modify, import, or migrate them, except that bootstrap Terraform sources MAY be read for backend configuration verification (Requirement 5 criterion 15) and SHALL NOT be modified.
6. WHEN inspection completes, THE Validator SHALL produce an inspection inventory listing every file read and every file that could not be read, and SHALL NOT issue any Recommendation until the inventory exists.

### Requirement 2: Safety and Read-Only Execution

**User Story:** As an operator, I want validation to be strictly read-only, so that no infrastructure, state, or pipeline is altered by testing.

#### Acceptance Criteria

1. THE Validator SHALL run only commands on the Read_Only_Command list and SHALL record each executed command in the Evidence.
2. THE Validator SHALL NOT run `terraform apply`, `destroy`, `import`, `state rm`, `state mv`, or `taint`.
3. THE Validator SHALL limit AWS calls to operations explicitly enumerated in the Read_Only_Command list, each of which is a Describe, Get, List, or metadata-only Head operation; any operation not enumerated SHALL be denied by default.
4. THE Validator SHALL NOT modify Terraform files, the Jenkinsfile, Jenkins job configuration, or Terraform state, such that checksums of those artifacts and the remote state object's version identifier, ETag, and LastModified (metadata obtained via `s3api head-object` on the state key `ecs-dev/terraform.tfstate`) are identical before and after a run; IF `head-object` access is unavailable, THEN THE Validator SHALL record that comparison BLOCKED naming the missing access.
5. IF a Check requires a non-read-only command, THEN THE Validator SHALL NOT run the command, SHALL record the Check BLOCKED with the reason and the command required, and SHALL request user approval before further action on that Check.
6. THE Validator SHALL redact secret values, credentials, and secret contents from all Evidence, replacing each with "REDACTED" and referencing secrets by name or ARN only.
7. THE Validator SHALL NOT commit or upload the Saved_Plan, its JSON renderings, or `terraform.tfstate` files (including `.backup`) to GitHub, and SHALL confirm these patterns are excluded by repository ignore rules.
8. WHEN a fix is identified, THE Validator SHALL record it as a proposal containing the affected file or resource and the proposed change, and SHALL make no change until the user gives explicit approval for that specific proposal.
9. IF a secret value appears in command output, THEN THE Validator SHALL omit it from Evidence, SHALL record the Check as FAIL with a note identifying the secret by name or ARN, and SHALL continue.
10. THE Validator SHALL apply every constraint in criteria 1 through 9 and 12 through 14 to Group A, Group B, and Group C Checks alike.
11. THE Validator SHALL limit ECR queries to metadata-only operations (`describe-repositories`, `describe-images`) and SHALL NOT pull an image, run `docker login`, or run any other login that writes credentials or state.
12. THE Validator SHALL NOT invoke any operation that returns or issues credentials or secret values, including `secretsmanager get-secret-value` and `batch-get-secret-value`, `ssm get-parameter(s)` with decryption, `ecr get-authorization-token` and `get-login-password`, `sts get-session-token` and `get-federation-token`, `sso get-role-credentials`, `kms decrypt`, `aws configure export-credentials` and `aws configure get`, and SHALL NOT use CLI flags that disclose or redirect (`--debug`, `--endpoint-url`, `--cli-input-json`, `--cli-input-yaml`, `--output-file` style redirection, `git --output`).
13. THE Validator SHALL NOT read credential files (for example `~/.aws/credentials`, `.env` files, private keys), SHALL inspect any Terraform state file (local or remote) only structurally (format version, Terraform version, serial, resource and output counts, resource types) and never print attribute values, and SHALL NOT run `terraform show` without a plan-file argument, `terraform state show`, `terraform state pull`, `terraform output`, `terraform refresh`, `terraform console`, or `terraform workspace new`, `select`, or `delete`.
14. THE Validator SHALL NOT run `terraform init`, and IF the Dev_Root is not initialized or `terraform validate` or `terraform state list` needs initialization, THEN THE Validator SHALL record the Check BLOCKED naming the missing initialization and SHALL request user approval.

### Requirement 3: Status Recording and Evidence Integrity

**User Story:** As a reviewer, I want each test recorded with a status and evidence, so that readiness conclusions are auditable.

#### Acceptance Criteria

1. THE Validation_Suite SHALL assign every Check exactly one Status at any time: PASS, FAIL, BLOCKED, or NOT TESTED.
2. WHEN a Check is created, THE Validator SHALL set its Status to NOT TESTED.
3. WHEN a Check is recorded PASS, THE Validator SHALL attach at least one Evidence item containing the observed output or file content and the expected result compared against.
4. IF a Check has no attached Evidence, THEN THE Validator SHALL reject the PASS, retain the prior Status, and report that Evidence is missing.
5. WHEN a Check is recorded FAIL, THE Validator SHALL record a reason stating the observed result that differed from the expected result.
6. WHEN a Check is recorded BLOCKED, THE Validator SHALL record a reason and the name of the missing prerequisite.
7. WHEN a Check is executed, THE Validator SHALL record a UTC timestamp with at least one-second resolution and the command executed or the file reference (path and line where applicable).
8. IF the Status of a Check is NOT TESTED, THEN THE Validator SHALL leave the timestamp, the command or file reference, and the Evidence empty.

### Requirement 4: Phase Classification

**User Story:** As a deployment owner, I want checks separated into pre-deployment and post-deployment, so that I know what can be proven now.

#### Acceptance Criteria

1. THE Validation_Suite SHALL classify every Check as exactly one of Pre_Deployment_Check or Post_Deployment_Check, such that 100% of Checks carry one classification and none carry both, and SHALL additionally assign every Check to exactly one Check_Group per criterion 8.
2. IF a Check has no classification, THEN THE Validator SHALL record the Check BLOCKED with the reason of missing classification and SHALL NOT record it PASS.
3. WHILE the DEV stack is not applied, THE Validator SHALL record each Post_Deployment_Check as NOT TESTED or BLOCKED and SHALL NOT record it PASS.
4. WHILE the DEV stack is not applied, THE Validator SHALL record each executed Pre_Deployment_Check as PASS, FAIL, or BLOCKED (naming the prerequisite for BLOCKED), and SHALL leave a Pre_Deployment_Check as NOT TESTED only before it is run.
5. THE Validation_Suite SHALL state, for each Post_Deployment_Check, the name of at least one deployed resource on which the Check depends.
6. THE Validation_Suite SHALL order Checks so that every Check appears after all Checks it declares as prerequisites.
7. IF a prerequisite Check does not record PASS, THEN THE Validator SHALL record each dependent Check BLOCKED with a reason naming the prerequisite, and SHALL NOT execute the dependent Check.
8. THE Validation_Suite SHALL assign every Check to exactly one Check_Group: Group A (Pre_Deployment_Check on infrastructure), Group B (Post_Deployment_Check on infrastructure), or Group C (application integration and CI/CD readiness tests, classified Pre_Deployment_Check when statically inspectable and Post_Deployment_Check otherwise).
9. WHILE the application image or Atlas data required by a Group C Check does not exist, THE Validator SHALL record that Group C Check as NOT TESTED or BLOCKED naming the missing image or data, and SHALL NOT record it PASS.

### Requirement 5: Terraform and Saved Plan Integrity

**User Story:** As a platform engineer, I want the configuration and saved plan verified, so that the reviewed plan matches what would be applied.

#### Acceptance Criteria

1. WHEN validating Terraform, THE Validator SHALL run `terraform fmt -check -recursive` and `terraform validate` against the Dev_Root and SHALL record the Check PASS only if both exit 0.
2. IF either command exits non-zero, THEN THE Validator SHALL record FAIL naming each file or resource address reported and SHALL NOT modify any file.
3. THE Validator SHALL confirm that the installed Terraform satisfies `~> 1.16.0` and the installed AWS provider satisfies `>= 6.67.0, < 7.0.0`, and SHALL record FAIL stating installed versus required versions for any unsatisfied constraint.
4. WHEN inspecting the Saved_Plan with `terraform show`, THE Validator SHALL confirm the summary is exactly 51 to add, 0 to change, and 0 to destroy, and SHALL record FAIL stating the actual counts if any differ.
5. IF the Saved_Plan contains any change, destroy, or replacement, THEN THE Validator SHALL record FAIL naming each resource address and planned action.
6. THE Validator SHALL compare the Saved_Plan modification time with the modification times of all Terraform sources under the Dev_Root and `ecs-terraform/modules/` and with `terraform.tfvars`, and SHALL list each file newer than the plan or with uncommitted changes per `git status` as a prompt to verify, not itself a failure; WHEN such a file exists, THE Validator SHALL inspect its `git diff` and the Saved_Plan content, and SHALL record a Risk Finding only if the file content differs from the Saved_Plan, or the file is newer than the Saved_Plan and a match cannot be verified; otherwise an Informational Finding.
7. THE Validator SHALL list the 51 planned resources grouped by module and resource type with counts, and SHALL record a Finding for any group with no corresponding resource definition in module sources or any module-source resource absent from the plan without an explained conditional.
8. WHEN checking remote state, THE Validator SHALL list state at key `ecs-dev/terraform.tfstate` using read-only state listing only, and SHALL compare the listing with the approved DEV bootstrap baseline consisting of EXACTLY these two existing Terraform-managed resources: `module.backend.aws_ecr_repository.app` and `module.backend.aws_ecr_lifecycle_policy.app`; THE Validator SHALL record PASS only if the listing equals the baseline exactly, SHALL record FAIL naming each unexpected resource address (Blocker for Bootstrap_Readiness and Application_Deployment_Readiness), and SHALL record FAIL with a Risk Finding for each missing baseline resource. Unexpected records are reviewed, never changed: no state-modifying command is run. Adjustment record: the original expectation was zero resources; on 2026-11-02 the user approved this baseline because the ECR repository and lifecycle policy were previously created through Terraform; the original zero-resource test was run first and was not met (2 resources), and that original result is preserved in Task 4.1 and CHK-TFP-008.
9. IF the state cannot be read, THEN THE Validator SHALL record FAIL stating the access error and SHALL NOT proceed to any state-modifying command.
10. THE Validator SHALL confirm that no 12-digit AWS account ID, `vpc-`, `subnet-`, or `sg-` identifier appears as a literal in Terraform sources, excluding values supplied through `terraform.tfvars` ARNs and values known only after apply, and SHALL record a Finding naming the file and line or resource address per occurrence.
11. IF a refreshed plan is required, THEN THE Validator SHALL request user approval first and, after approval, SHALL run `terraform plan` with `-lock=false` and `-refresh-only` without `-out`, leaving the Saved_Plan unmodified.
12. IF the user declines or does not respond to the approval request in criterion 11, THEN THE Validator SHALL record a Finding that the Saved_Plan is unverified as current and SHALL NOT run `terraform plan`.
13. THE Validator SHALL inspect every local `*.tfstate` file in the repository (structural metadata only, per Requirement 2 criterion 13), SHALL record each as a Finding (Informational if it contains zero resources and is untracked or git-ignored, as housekeeping where any deletion is a proposal pending approval; Risk if it contains resources; Blocker only if it is the state configured for the Dev_Root), and SHALL record that local state files are not the remote state at key `ecs-dev/terraform.tfstate`. THE Validator SHALL NOT modify, move, rename, truncate, or delete any local state file (including empty shells); deletion is only a proposal pending explicit user approval.
14. THE Validator SHALL treat the binary Saved_Plan as the source of truth and SHALL compare the modification times of its JSON renderings with the binary plan; IF a rendering is older than the binary plan, THEN THE Validator SHALL NOT derive any Evidence from that rendering, SHALL derive plan data from the binary plan in memory via `terraform show -json`, and SHALL record a Finding that the rendering is stale.
15. THE Validator SHALL inspect the initialized backend metadata (`.terraform/terraform.tfstate`) structurally, SHALL confirm the key equals `ecs-dev/terraform.tfstate` and that no `access_key`, `secret_key`, `token`, or `sse_customer_key` is set, and SHALL record state encryption and state locking each as one of CONFIRMED_ENABLED, UNVERIFIED, or CONFIRMED_DISABLED. Unset or absent keys in the initialized backend metadata (`.terraform/terraform.tfstate`) SHALL be treated as "not stated", never as evidence of disabled. THE Validator SHALL attempt confirmation from (a) the bootstrap and backend configuration sources (`ecs-terraform/bootstrap/*.tf`, `backend.config` key names only) and (b) read-only AWS metadata of the state bucket (`s3api get-bucket-encryption`, `s3api get-bucket-versioning`, and, only if the bootstrap sources define a lock table, `dynamodb describe-table`). THE Validator SHALL record a Risk Finding only for UNVERIFIED (stating that confirmation was not possible, with the reason), SHALL record a Risk-or-higher Finding for CONFIRMED_DISABLED backed by explicit evidence, and SHALL record CONFIRMED_ENABLED as Informational.

### Requirement 6: Networking Validation

**User Story:** As a platform engineer, I want networking verified, so that private tasks can reach required services without public exposure.

#### Acceptance Criteria

1. THE Validator SHALL confirm the plan creates exactly one VPC, two public subnets, two private subnets, one Internet Gateway, one public route table and one private route table (each with an association for every subnet it serves), and that each subnet CIDR and the VPC CIDR equals the value in `terraform.tfvars`.
2. WHERE `enable_nat_gateway = true`, THE Validator SHALL confirm exactly one NAT Gateway in a public subnet, exactly one Elastic IP attached, and a `0.0.0.0/0` route in the private route table targeting that NAT Gateway.
3. THE Validator SHALL confirm exactly one S3 Gateway endpoint is planned and associated with both the public and private route tables.
4. THE Validator SHALL confirm the two private subnets are in two distinct Availability Zones within the configured region.
5. IF the plan has no interface VPC endpoints, THEN THE Validator SHALL record that ECR (API and Docker), Secrets Manager, and CloudWatch Logs traffic depends on the NAT Gateway, marked as an accepted dependency rather than a failure.
6. IF any private subnet is planned with `map_public_ip_on_launch = true` or a route to the Internet Gateway, THEN THE Validator SHALL record FAIL identifying the subnet and SHALL mark networking validation failed.
7. WHEN the NAT Gateway Elastic IP is known after deployment, THE Validator SHALL record a Post_Deployment_Check stating this IP must be added to the MongoDB Atlas IP access list, listing the IP as the value to add.

### Requirement 7: Security Group and IAM Validation

**User Story:** As a security reviewer, I want security groups and IAM reviewed, so that access follows least privilege.

#### Acceptance Criteria

1. THE Validator SHALL confirm the ALB security group has exactly one ingress source, the AWS-managed CloudFront origin-facing prefix list, restricted to the ALB listener port, and SHALL record a Finding for any other source, CIDR, or port.
2. THE Validator SHALL confirm the ECS security group has exactly one ingress source, the ALB security group, restricted to the container port, and SHALL record a Finding for any other.
3. THE Validator SHALL list every `0.0.0.0/0` rule (ingress and egress) with a written justification or as a Finding, and SHALL record an explicit "none found" if there are zero.
4. THE Validator SHALL confirm the ECS execution role has exactly two permission sources, `AmazonECSTaskExecutionRolePolicy` and one Secrets Manager read policy whose Resource entries are exact secret ARNs with no wildcard, and SHALL record a Finding for any additional or broader permission.
5. THE Validator SHALL confirm the ECS task role has no `AdministratorAccess`, no Action of `*` or `<service>:*`, and no Resource of `*` except where the action does not support resource-level permissions, and SHALL record each exception as a Finding with justification.
6. THE Validator SHALL confirm every ECS IAM role trust policy names only `ecs-tasks.amazonaws.com` and includes both `aws:SourceAccount` and `aws:SourceArn` conditions, and SHALL record a Finding otherwise.
7. THE Validator SHALL confirm zero `aws_iam_user` and zero `aws_iam_access_key` resources, and SHALL record a Finding for each present.
8. THE Validator SHALL record where `distinct()` is applied to the duplicated secret ARN, SHALL confirm the secret-read policy has exactly one Resource entry for that ARN, and SHALL record a Finding if the ARN appears more than once.
9. IF the secret ARN is encrypted with a customer-managed KMS key, THEN THE Validator SHALL record a Finding that the execution role requires `kms:Decrypt` on that key ARN, and SHALL record a further Finding if the plan does not grant it.

### Requirement 8: CloudFront and S3 Validation

**User Story:** As a platform engineer, I want the edge verified, so that the frontend and API paths behave as designed.

#### Acceptance Criteria

1. THE Validator SHALL confirm all four S3 public-access-block flags are true and SSE-S3 (AES256) is configured.
2. THE Validator SHALL confirm exactly one bucket policy statement grants `s3:GetObject`, with the CloudFront service principal as principal, conditioned on the edge distribution ARN.
3. THE Validator SHALL confirm the S3 origin uses OAC with signing behavior "always" and SigV4, the origin domain is the regional bucket domain name, and zero OAI resources exist.
4. THE Validator SHALL confirm `default_root_object` equals "index.html".
5. THE Validator SHALL confirm exactly two ordered behaviors `/api/*` and `/v1/*`, each routing to the VPC Origin, using the caching-disabled cache policy, allowing all seven HTTP methods, with viewer protocol policy redirect-to-https.
6. THE Validator SHALL confirm the VPC Origin target ARN is the internal ALB ARN from backend output `alb_arn`, the origin protocol policy is http-only, and the HTTP port is 80.
7. THE Validator SHALL confirm `cloudfront_default_certificate` is true and zero ACM certificate and zero Route 53 resources are planned.
8. WHILE `enable_waf` is false, THE Validator SHALL confirm `web_acl_id` is null and zero WAF web ACL resources are planned.
9. THE Validator SHALL record a Finding, as a Known_Limitation, that the S3 bucket has 0 objects after deployment, requests for `index.html` return an error until a frontend is uploaded, and no custom error response is configured, with a Blocks_Field naming Application_Deployment_Readiness and criterion 11 of this requirement, classified Informational for Bootstrap_Readiness and Blocker for Application_Deployment_Readiness.
10. THE Validator SHALL record a Finding that requests to routes outside `/api/*` and `/v1/*` (including `/docs` and `/health`) are served by the S3 default behavior, not the backend, with a Blocks_Field naming any Application_Deployment_Readiness criterion requiring such a route, classified Informational for Bootstrap_Readiness and Risk for Application_Deployment_Readiness.
11. WHEN the distribution is deployed, THE Validator SHALL verify, as a Post_Deployment_Check, that an HTTPS request to the CloudFront domain completes a TLS handshake and returns an HTTP response within 10 seconds, and SHALL record a Finding if not.
12. IF any of criteria 1 through 8 does not match, THEN THE Validator SHALL record a Finding with the failed check, the expected and observed values, and SHALL mark edge validation failed.

### Requirement 9: ECS, ALB, and Image Validation

**User Story:** As a platform engineer, I want the compute path verified, so that the first task start succeeds when scaled up.

#### Acceptance Criteria

1. THE Validator SHALL confirm the ECS launch type is Fargate, every service subnet is private, and `assign_public_ip = false`, and SHALL record a Blocker for each attribute that does not match.
2. THE Validator SHALL confirm `desired_count = 0`, autoscaling `min_capacity = 0`, and `max_capacity = 2`, and SHALL record a Blocker for each that differs.
3. THE Validator SHALL confirm the ALB scheme is internal, all ALB subnets are private, and exactly one HTTP listener forwards to a target group of type IP whose port equals `container_port`, and SHALL record a Blocker for each mismatch.
4. THE Validator SHALL NOT assume the ECR repository is missing, and SHALL verify the existing ECR repository and image tag `sha-a454df4` against (a) the current Terraform state and remote state listing, (b) the Saved_Plan, recording whether the repository is planned for creation, import-needed, or already managed, and (c) read-only AWS ECR metadata.
5. THE Validator SHALL obtain the ECR metadata using only `describe-repositories` and `describe-images` (no image pull and no login that writes), and SHALL record the tag, image digest, and tag immutability setting as Evidence.
6. THE Validator SHALL distinguish three facts separately for the planned repository name: exists in AWS (`describe-repositories`), managed by Terraform (present in `state list`), and creation conflict (plan action create while the repository exists in AWS and not in state), comparing repository names exactly (case-sensitive) using the name from the Saved_Plan; and THE Validator SHALL record exactly one of these ECR outcomes: (a) the repository exists in AWS and in state; (b) the repository exists in AWS but not in state while the Saved_Plan would create it, which is a name conflict where apply would fail with RepositoryAlreadyExists and is a Blocker for Bootstrap_Readiness, with a resolution proposal (for example, import) pending approval and no automatic action; or (c) the repository does not exist in AWS.
7. IF AWS read access for ECR is unavailable, THEN THE Validator SHALL record the ECR Checks BLOCKED naming the missing access; THE Validator SHALL NOT record them BLOCKED for any other reason, and SHALL NOT create the repository or push any image.
8. THE Validator SHALL record a Finding, as a Known_Limitation, that the Landing_Page_Image is not the LMS_API, and that `health_check_path = "/"` and `container_port = 3000` are valid for the landing page only, with a Blocks_Field naming Application_Deployment_Readiness and criterion 13 of this requirement, classified Informational for Bootstrap_Readiness and Blocker for Application_Deployment_Readiness.
9. THE Validator SHALL record the changes required to run the LMS_API (container port, health check path, and consumption of `MONGODB_URL` and `STAFF_ADMIN_MONGO_URL`) as proposals "pending approval", modifying no Terraform, tfvars, or Saved_Plan, and SHALL classify the related Finding Informational for Bootstrap_Readiness and Blocker for Application_Deployment_Readiness with a Blocks_Field naming the prevented criteria.
10. IF `aws_ecs_service.app` declares no `lifecycle.ignore_changes` for `desired_count` while Application Auto Scaling manages that value, THEN THE Validator SHALL record a Finding stating that a later `terraform apply` could reset the autoscaled task count, and SHALL also register it per Requirement 16.
11. THE Validator SHALL confirm `MONGODB_URL` and `STAFF_ADMIN_MONGO_URL` are each injected as secrets from a Secrets Manager ARN and `DB_NAME` and `STAFF_ADMIN_DB_NAME` are plain environment values, and SHALL record a Blocker for each that is missing or injected differently.
12. THE Validator SHALL confirm ECR image tag mutability is IMMUTABLE, SHALL record whether a lifecycle policy is present or absent, and SHALL record a Blocker if mutability is not IMMUTABLE.
13. WHEN tasks are scaled above zero after deployment, THE Validator SHALL verify, as a Post_Deployment_Check, that RUNNING tasks equal the desired count within 300 seconds and all ALB targets are healthy within 300 seconds of RUNNING, and SHALL record the stopped-task or unhealthy-target reason on failure.
14. WHEN the repository named in the Saved_Plan does not exist in AWS, THE Validator SHALL list ECR repositories (`describe-repositories`) and look for image tag `sha-a454df4` (`describe-images`) in any other repository, and IF found, SHALL record a Finding that the image resides in a repository different from the one the task definition will reference (repository name and masked URL), classified Risk for Bootstrap_Readiness (`desired_count = 0` starts no task) and Blocker for Application_Deployment_Readiness, with a proposal (for example re-tag and push, or change the repository name) pending approval.

### Requirement 10: MongoDB Atlas Prerequisites

**User Story:** As a platform engineer, I want Atlas readiness verified, so that the application can connect once deployed.

#### Acceptance Criteria

1. THE Validator SHALL confirm the secret in `app_secret_arn` exists in us-east-1 using metadata-only `describe-secret`, and SHALL NOT retrieve the secret value.
2. IF `describe-secret` returns not-found, access-denied, or no response within 30 seconds, THEN THE Validator SHALL record FAIL (not-found), BLOCKED (access-denied), or BLOCKED (timeout) respectively, without recording any secret value or part of the connection URI.
3. THE Validator SHALL record whether `app_secret_arn` and `staff_admin_secret_arn` resolve to the same ARN, and that both databases (`teacher_student_db`, `admin_staff_mongodb`) use one Atlas user.
4. WHEN the NAT Gateway Elastic IP is known, THE Validator SHALL record the expected Atlas access list entry as that address with `/32`.
5. IF the Atlas access list contains `0.0.0.0/0`, THEN THE Validator SHALL record a Finding.
6. THE Validator SHALL record a Finding, as a Known_Limitation, that the Atlas cluster is empty and that indexes are created by the LMS_API at startup, not by Terraform, with a Blocks_Field naming Application_Deployment_Readiness and the Atlas connectivity Check, classified Informational for Bootstrap_Readiness and Blocker for Application_Deployment_Readiness.
7. IF the NAT Elastic IP is not known or the access list lacks it as `/32`, THEN THE Validator SHALL record the Atlas connectivity Check BLOCKED and SHALL state which condition caused it.
8. THE Validator SHALL record Atlas connectivity from ECS as a Post_Deployment_Check and SHALL NOT mark it PASS or FAIL before deployment.

### Requirement 11: Observability Validation

**User Story:** As an operator, I want monitoring verified, so that failures are visible after deployment.

#### Acceptance Criteria

1. THE Validator SHALL confirm exactly one ECS application log group with 7-day retention, and SHALL record a Finding if it is absent or different.
2. THE Validator SHALL list every planned CloudWatch alarm and the dashboard by name, SHALL confirm dimensions reference backend or edge module outputs rather than hardcoded identifiers, and SHALL record a Finding for each hardcoded dimension.
3. WHILE `enable_observability_sns` is false, THE Validator SHALL record zero SNS topics and subscriptions and no alarm actions, so that alarms notify no recipients.
4. WHILE the WAF, CloudTrail, and security-alert toggles are disabled, THE Validator SHALL record zero such resources, and SHALL record a Finding for any that appears.
5. WHEN alarms are planned with `desired_count = 0`, THE Validator SHALL record as a Finding each alarm that can enter ALARM or INSUFFICIENT_DATA because no tasks run, stating the alarm name and state.
6. WHEN the stack is deployed, THE Validator SHALL verify as Post_Deployment_Checks that (a) at least one log event is in the ECS log group within 5 minutes of the first running task starting, and (b) each alarm's state is recorded, with a Finding for each alarm not OK.
7. IF an item in criteria 1 through 6 cannot be verified because plan data or a deployed resource is unavailable, THEN THE Validator SHALL mark the item BLOCKED or NOT TESTED with the reason and SHALL NOT mark it PASS.

### Requirement 12: CI/CD Readiness

**User Story:** As a release engineer, I want Jenkins readiness assessed, so that deployments are repeatable without changing the pipeline.

#### Acceptance Criteria

1. THE Validator SHALL search the whole repository, excluding `.git/` and `node_modules/`, for files named `Jenkinsfile` and SHALL record each repository-relative path as Evidence.
2. IF no Jenkinsfile is tracked by Git, THEN THE Validator SHALL record one Finding and SHALL record each Check depending on pipeline content BLOCKED.
3. THE Validator SHALL NOT create, modify, or delete any Jenkins pipeline file, job configuration, or credential.
4. THE Validator SHALL record as Evidence whether `modules/cicd/` contains zero `.tf` files and that the Jenkins host, IAM role, and credentials are not managed by this plan.
5. WHERE Jenkins build logs or pipeline output are available, THE Validator SHALL record the ECR repository name, image tag, and AWS account ID of the most recent push as Evidence, with the account ID masked to its last 4 digits.
6. IF build logs are unavailable, THEN THE Validator SHALL record the repository, tag, and account Checks BLOCKED and SHALL NOT infer these values.
7. THE Validator SHALL confirm the backend bucket, key, and region are supplied through `-backend-config` arguments or a backend config file, and SHALL record a Finding for each committed file containing an AWS access key ID, secret access key, or session token.
8. THE Validator SHALL confirm `.gitignore` contains a pattern matching Saved_Plan files and `git ls-files` returns zero tracked Saved_Plan files, and SHALL record a Finding for each tracked match.
9. IF the Jenkins pipeline is not available for inspection, THEN THE Validator SHALL record every Check requiring pipeline content BLOCKED and SHALL state the missing input in Evidence.

### Requirement 13: Deployment Blockers and Mismatches

**User Story:** As a deployment owner, I want blockers and mismatches consolidated, so that I can decide whether to proceed.

#### Acceptance Criteria

1. THE Validator SHALL maintain a Findings register in which each Finding has a unique identifier, a severity, at least one affected resource, at least one Evidence item (file path with line number or command output excerpt), and a proposed fix, and a Blocks_Field naming the Readiness_Level, phase, or acceptance criterion the Finding prevents.
2. THE Validator SHALL classify each Finding, separately for Bootstrap_Readiness and Application_Deployment_Readiness, as exactly one of Blocker (at that level, would cause `terraform apply` of the Saved_Plan to fail, violate a steering rule on security, state, or scope, or prevent a named acceptance criterion), Risk (no failure but could cause incorrect behavior, unexpected cost, or reduced security), or Informational (no impact at that level); steering rules on security, state, or scope are the only steering rules that make a deviation a Blocker, and other deviations (for example hardcoded identifiers that do not break apply) are Risk.
3. THE Validator SHALL compare `terraform.tfvars` comments with actual values and SHALL record each comment contradicted by a tfvars or Saved_Plan value as a separate Finding (for example, a comment saying no image has been pushed while `image_tag = "sha-a454df4"`).
4. THE Validator SHALL compare steering rules with implemented modules and SHALL record each deviation as a separate Finding citing the steering rule and the module file path.
5. WHEN the working tree has an uncommitted change to `modules/edge/cloudfront.tf` or any other file, THE Validator SHALL first verify the current `git diff` and the Saved_Plan content, SHALL record what the diff changes and whether each changed attribute appears in the Saved_Plan, and SHALL classify the Finding Blocker only if the Saved_Plan lacks a diffed attribute (lacks meaning the attribute is absent from the Saved_Plan or present with a different value), otherwise Informational ("uncommitted but reflected in plan"), adding a Risk only if the source differs from the Saved_Plan or is newer than the Saved_Plan and a match cannot be verified.
6. IF a Finding has a proposed fix, THEN THE Validator SHALL mark the fix awaiting approval and SHALL make no change until explicit user approval.
7. WHEN all Checks complete, THE Validator SHALL report the Finding count per classification for each Readiness_Level and SHALL report that the corresponding deployment cannot proceed if the Blocker count for that Readiness_Level is greater than zero.
8. THE Validator SHALL record each Known_Limitation (Landing_Page_Image, empty S3 frontend, unpopulated Atlas cluster) as a Finding classified Blocker only for Application_Deployment_Readiness (or the specific acceptance criteria it prevents) and Informational or Risk for Bootstrap_Readiness.
9. THE Validator SHALL assign severities so that the Application_Deployment_Readiness severity is never lower than the Bootstrap_Readiness severity for the same Finding (Blocker > Risk > Informational), so that every Bootstrap_Readiness Blocker is also an Application_Deployment_Readiness Blocker.
10. WHEN a Check is recorded FAIL, THE Validator SHALL link the Check to at least one Finding.

### Requirement 14: Cost Estimation

**User Story:** As a budget owner, I want recurring charges estimated, so that DEV spend is known before apply.

#### Acceptance Criteria

1. THE Validator SHALL list every planned resource type that incurs ongoing charges with its resource type name and planned instance count.
2. THE Validator SHALL report the estimated monthly USD cost, rounded to two decimals, for each of NAT Gateway, Elastic IP, internal ALB, CloudFront, S3, CloudWatch Logs and alarms, ECR storage, and Secrets Manager, plus a total.
3. THE Validator SHALL state for each estimate the region, hours per month (730), data transfer GB/month, log ingestion and storage GB/month, alarm count, and secret count, and SHALL cite the AWS pricing page URL and retrieval date per unit price.
4. WHILE `desired_count = 0`, THE Validator SHALL exclude Fargate compute from the total and SHALL state the Fargate hourly USD cost for one task at the configured vCPU and memory.
5. THE Validator SHALL identify each resource that incurs charges while idle and each resource that can be removed or disabled to reduce cost, labeled as a proposal pending approval, without modifying anything.
6. IF a unit price cannot be retrieved or is unavailable for the region, THEN THE Validator SHALL mark that estimate "unavailable" (classified UNKNOWN per criterion 7) with the reason, exclude it from the total, and state that the total is incomplete.
7. THE Validator SHALL classify every cost line as exactly one of FIXED_HOURLY (charged per hour or per month while the resource exists, regardless of use, for example NAT Gateway hours, public IPv4 address hours, ALB hours, Secrets Manager secret-months, CloudWatch alarm-months and dashboard-months), USAGE_BASED (charged by consumption, for example NAT data processed, ALB LCUs, CloudFront requests and data transfer, S3 requests and storage, CloudWatch Logs ingestion and storage, ECR storage, Secrets Manager API calls, Fargate vCPU and GB-hours), or UNKNOWN (unit price or quantity unavailable); SHALL report subtotals for FIXED_HOURLY and USAGE_BASED separately; SHALL list UNKNOWN lines by name, excluded from totals; and SHALL state the total as incomplete while any UNKNOWN line exists. Usage-based estimates SHALL state the assumed quantity and label it an assumption.

### Requirement 15: Deliverables

**User Story:** As a stakeholder, I want structured deliverables, so that the validation can be reviewed and repeated.

#### Acceptance Criteria

1. WHEN a validation run completes, THE Validation_Suite SHALL produce exactly four deliverables: the requirements document, the validation design, the ordered task list, and the Readiness_Report.
2. THE Readiness_Report SHALL present Checks grouped as Group A, Group B, and Group C, listing every Check with exactly one Status, an Evidence reference for each PASS and FAIL Check, and a reason (and missing prerequisite) for each BLOCKED Check.
3. THE Readiness_Report SHALL contain the Findings register, the cost estimate, and two verdicts, one for Bootstrap_Readiness and one for Application_Deployment_Readiness, each exactly one of NOT READY, READY WITH CONDITIONS, or READY.
4. IF any Blocker affecting a Readiness_Level is open, THEN THE Readiness_Report SHALL state the verdict NOT READY for that Readiness_Level.
5. IF no Blocker affecting a Readiness_Level is open AND at least one in-scope Check has Status NOT TESTED or BLOCKED, THEN THE Readiness_Report SHALL state READY WITH CONDITIONS for that Readiness_Level and SHALL list each such Check by name with its Status; in-scope Checks are Groups A and B for Bootstrap_Readiness and Groups A, B, and C for Application_Deployment_Readiness.
6. IF no Blocker affecting a Readiness_Level is open AND every in-scope Check has Status PASS, THEN THE Readiness_Report SHALL state READY for that Readiness_Level; READY requires every in-scope Check to be PASS.
7. THE Readiness_Report SHALL contain zero secret values and SHALL reference the Saved_Plan by filename only, without embedding its content.
8. IF a Check has no recorded Evidence, THEN THE Validator SHALL NOT record the Check PASS and SHALL record a Finding identifying the missing Evidence.
9. IF the Bootstrap_Readiness verdict is NOT READY, THEN THE Readiness_Report SHALL state the Application_Deployment_Readiness verdict as NOT READY.

### Requirement 16: Mandatory Findings Register Entries

**User Story:** As a deployment owner, I want key risks always recorded as dedicated findings, so that they cannot be lost inside other checks.

#### Acceptance Criteria

1. THE Validator SHALL record in the Findings register a dedicated Finding for each of criteria 2 through 5, each with a unique identifier, a severity for Bootstrap_Readiness and a severity for Application_Deployment_Readiness, the phase (Pre_Deployment_Check or Post_Deployment_Check and Check_Group), Evidence, and a proposed fix marked awaiting approval.
2. THE Validator SHALL record a Finding for ECS `desired_count` drift stating whether `aws_ecs_service.app` lacks `lifecycle.ignore_changes` for `desired_count` while Application Auto Scaling manages that value with `min_capacity = 0`.
3. THE Validator SHALL record a Finding that SNS notifications are disabled and no recipients are configured, so that alarms notify no one.
4. THE Validator SHALL record a Finding that the NAT Gateway Elastic IP must be added to the MongoDB Atlas IP access list after deployment, as a Post_Deployment_Check with a Blocks_Field naming Atlas connectivity.
5. THE Validator SHALL record a Finding summarizing ongoing AWS costs, referencing the Requirement 14 totals and listing the resources that incur charges while idle.
6. IF the condition described in any of criteria 2 through 5 is not present in the configuration, THEN THE Validator SHALL record the Finding as Informational stating the condition is absent, and SHALL NOT omit it.
