# Bootstrap Deployment Runbook (DEV) — For Review Only

Project: ecs-terraform-cicd · Environment: dev · Profile: charltonecs · Region: us-east-1
Authoritative saved plan: `ecs-terraform/envs/dev/tfplan-dev-lockfile`
Verdict carried in: GO WITH CONDITIONS (bootstrap at `desired_count = 0`)

This runbook is a proposal. Nothing in it has been executed. Every apply/destroy step is gated on explicit approval at the checkpoints marked **[APPROVAL]**. `terraform apply` remains unauthorized.

## 1. Prerequisites and the exact apply command

Prerequisites already verified (do not re-run):
- Dev root initialized against the S3 backend; remote state holds exactly the two pre-existing ECR resources.
- `terraform validate` passed; `fmt -check` clean; plan is 51 create, 0 change, 0 destroy (plus the 2 ECR no-ops and 1 data read), Terraform 1.16.4, AWS provider 6.67.0.
- Capacity verified: IGW 0/5, VPC 0/5, EIP 0/5, NAT/AZ 0/5 in us-east-1a; no CIDR overlap with 10.0.0.0/16.
- Name conflicts: IAM policy, dashboard, CloudFront OAC names all free.
- ECR image `sha-a454df4` is OCI index with linux/amd64, digest matches; task def default X86_64/LINUX.
- Frontend bucket name currently free (404), subject to the global-name race.
- AWS identity reachable via `sts get-caller-identity` (operator is an IAM user with AdministratorAccess).

Operator prerequisites to confirm at apply time:
- `AWS_PROFILE=charltonecs`, region us-east-1, working dir `ecs-terraform/envs/dev`.
- State lock available: the backend uses **S3 native lockfile locking (`use_lockfile = true`)**. The apply writes a `.tflock` lock object alongside the state object in the same S3 bucket; no DynamoDB lock table is used. The apply takes the same S3 lockfile mechanism the plan used.
- The saved plan file `tfplan-dev-lockfile` is unmodified since it was generated.

Exact future apply command (run only after **[APPROVAL #1]**, from `ecs-terraform/envs/dev`):

```
AWS_PROFILE=charltonecs AWS_REGION=us-east-1 terraform apply -input=false -lock=true -lock-timeout=60s tfplan-dev-lockfile
```

Notes: applying a saved plan file takes no further variable input and re-locks state via the S3 lockfile. Do not run `terraform plan`/`apply` to regenerate; the saved plan is authoritative. If Terraform reports the saved plan is stale (state moved since it was captured), stop and re-plan under a separate approval rather than forcing it.

## 2. Expected costs and partial-deployment charges

From the recorded cost finding (`FND-COST`, incomplete total): about **62.93 USD/month** at idle — roughly 56.93 fixed plus 6.01 usage — with CloudFront data transfer, VPC origin, and OAC not yet priced.

Main recurring drivers at idle, bootstrap (desired_count = 0):
- NAT Gateway: hourly charge accrues as soon as it exists, even with no tasks running. This is the largest always-on cost.
- Elastic IP / public IPv4 address: **a public IPv4 address can incur an hourly charge even while associated with a running NAT Gateway.** AWS bills in-use public IPv4 addresses hourly, so the EIP attached to the NAT is not free; treat it as an always-on line item alongside the NAT itself.
- ALB: hourly charge once created, independent of task count.
- CloudWatch log group, ECR storage: minor.
- ECS Fargate tasks: **0** at bootstrap because `desired_count = 0`, so no task compute cost until scale-up.

Partial-deployment charge risk: if apply fails partway, any resources already created (NAT, ALB, EIP/public IPv4) begin billing immediately. Section 7 covers recovery so you don't leave orphaned billable resources.

## 3. Bootstrap sequence (desired_count = 0, min_capacity = 0)

The plan already sets ECS `desired_count = 0` and autoscaling `min_capacity = 0`, so this sequence creates infrastructure without starting any application task.

1. **[APPROVAL #1]** Confirm go for `terraform apply tfplan-dev-lockfile`.
2. Apply creates (single pass): VPC, 2 public + 2 private subnets, IGW, route tables + associations, 1 NAT in us-east-1a, 1 EIP, S3 gateway endpoint; ALB (internal), target group, listener; security groups; ECS cluster, task definition, service at desired_count 0; IAM execution + task roles; CloudWatch log group; autoscaling target/policies at min 0; S3 frontend bucket + OAC; CloudFront distribution + VPC origin.
3. No ECS task starts (desired_count 0). No scale-out can occur yet (min_capacity 0) — this is intended.
4. Proceed to Section 4 verification before any scale-up.

Expected end state: all infrastructure present, zero running tasks, empty frontend bucket (CloudFront default behavior will 403 until a frontend is uploaded — known limitation, Application blocker only).

## 4. Post-apply verification (AWS + Terraform state)

Read-only checks after apply (no changes):
- `terraform state list` shows the full set (previous 2 ECR + the newly created resources); no unexpected addresses.
- Outputs resolve: `vpc_id`, `public_subnet_ids`, `private_subnet_ids`, `alb_arn`, `alb_dns_name`, `ecr_repository_url`, `ecs_cluster_name`, `ecs_service_name`, `cloudfront_distribution_id`, `cloudfront_domain_name`, `frontend_bucket_name`.
- ECS service: `aws ecs describe-services` shows runningCount 0, desiredCount 0, no failed events.
- ALB target group: healthy/unhealthy counts both 0 (no targets yet — expected at desired_count 0).
- NAT: `describe-nat-gateways` state available in us-east-1a; EIP associated.
- CloudFront: distribution Deployed; default domain reachable (will 403 on empty bucket — expected).
- State fingerprint: new state object exists at `ecs-dev/terraform.tfstate`; record VersionId/ETag for the new baseline.

**[APPROVAL #2]** Confirm verification clean before networking/Atlas wiring.

## 5. NAT Elastic IP identification and MongoDB Atlas allowlist

Atlas M0 has no VPC peering/PrivateLink, so private ECS tasks reach Atlas over the NAT's stable egress IP, which must be allowlisted (`CHK-ATL-004`, currently NOT TESTED because it depends on the applied NAT).

Procedure (after apply, read-only on the AWS side):
1. Identify the NAT public IP: from `aws ec2 describe-nat-gateways` (NatGatewayAddresses[].PublicIp) or the Terraform EIP output. This is the single stable egress IP.
2. In the Atlas console (external, outside Terraform): add that IP as a `/32` entry to the project IP access list for the cluster. Atlas is provisioned manually; nothing here is Terraform-managed.
3. Confirm the Atlas M0 cluster, database, and database user exist, and that the connection URI is stored in AWS Secrets Manager (referenced by ARN as `MONGODB_URL`). The URI is never placed in Terraform, tfvars, the image, or any committed file.
4. Note the recorded finding: both Mongo URL env vars use the same secret ARN (Informational/Risk) — acceptable for DEV, flagged for later credential separation.

**[APPROVAL #3]** Confirm the NAT egress IP is allowlisted and the secret resolves before scale-up.

## 6. ECS application scale-up and Jenkins deployment (separate stages)

These are deliberately separate from bootstrap and from each other.

Stage 6a — ECS scale-up (infrastructure-side, Terraform or controlled change):
- Raise `desired_count` and autoscaling `min_capacity` from 0 to the intended DEV values.
- Before this, resolve `FND-ECS-DRIFT`: add `ignore_changes = [desired_count]` so autoscaling and Terraform don't fight over the count. The "zero-task service cannot scale from zero" note means min_capacity must be raised for scaling to function.
- This is a new plan/apply cycle under its own **[APPROVAL #4]** — not part of the saved bootstrap plan.

Stage 6b — Jenkins application deployment (application-side, via Jenkinsfile):
- Jenkins builds the image, pushes to ECR with an immutable tag (commit SHA / build number), and deploys the task definition to ECS. Verification uses the CloudFront entry point, not the internal ALB.
- Jenkins must use its own least-privilege role — not the operator's AdministratorAccess, and not reused credentials (steering: no AdministratorAccess for CI/CD).
- Jenkins infrastructure/IAM belongs to the cicd module; the pipeline logic stays in the repo `Jenkinsfile`.
- Jenkins/Atlas inputs are still not provided, so the related checks remain BLOCKED until they are supplied. **[APPROVAL #5]** gates enabling the Jenkins stage.

## 7. Partial-failure recovery and teardown (both gated)

Partial-failure recovery:
- If apply fails midway, read the error and `terraform state list` to see what was actually created. Do not hand-delete AWS resources — that desyncs state.
- **Do not assume `tfplan-dev-lockfile` can be reused after a partial apply.** A saved plan is computed against the state as it was at plan time; a partial apply has already changed state, so the saved plan is very likely stale. First inspect the state and the error, identify what exists versus what is missing, then — if continuing — **prepare a fresh plan under a separate approval** (`[APPROVAL]` for a new plan) rather than re-running the old saved plan file. Only re-use `tfplan-dev-lockfile` if inspection positively confirms state did not change (for example the failure happened before any resource was created); otherwise treat it as invalid.
- Watch for billable orphans (NAT, ALB, EIP/public IPv4) created before the failure; they bill immediately. Decide explicitly whether to continue (via a new plan) or tear down.
- If a bucket-name race (`FND-EDG-005`) causes a BucketAlreadyExists failure, the remedy is a name suffix (source change + a new plan), under approval — not a retry of the saved plan.

Teardown (only under a separate explicit approval — this is destructive and out of current scope):
- `terraform destroy` would remove all created DEV resources. It must never run without **[APPROVAL — TEARDOWN]** naming it specifically.
- Atlas (external) is not destroyed by Terraform; the NAT IP would be removed from the Atlas allowlist manually.
- This runbook does not authorize teardown; it only documents that the path requires its own approval.

## 8. Remaining risks, assumptions, approval checkpoints

Residual risks (carried from findings):
- SCP effect on service-linked role creation — only observable at apply (the Application Auto Scaling ECS SLR and CloudFront VPC Origin SLR are absent; simulation says creation is allowed, but an SCP isn't covered by simulation).
- `FND-EDG-005` global bucket-name race — only resolvable at apply.
- `FND-SEC-HIST-001` — OPEN documented residual risk (Low Risk/Informational): historical plans in public Git history, no credentials detected but not confirmed secret-free.
- Single NAT in one AZ — sole egress path and cross-AZ for us-east-1b (Informational for bootstrap, Risk for application).
- Empty frontend bucket 403s, `/health` and `/docs` served by S3, HTTP-only VPC-origin hop, default-cert TLS floor — Application-level, not bootstrap blockers.

Assumptions:
- The saved plan still matches state at apply time (and, per Section 7, is treated as invalid after any partial apply).
- State locking works at apply via the S3 native lockfile (inferred PASS, not directly observed).
- Atlas M0 and its user already exist and the secret is populated.

Approval checkpoints in order: **#1** apply bootstrap -> **#2** post-apply verification -> **#3** NAT IP allowlisted + secret resolves -> **#4** ECS scale-up (new plan, with ignore_changes fix) -> **#5** enable Jenkins deployment -> **TEARDOWN** (separate, destructive).
