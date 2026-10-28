# Security Architecture Review Findings — EruditionTX DEV (08-security)

Read-only review of the implemented Terraform, the security module README, and the latest
saved DEV plan (`envs/dev/tfplan-dev` / `tfplan-dev.json`: **53 add, 0 change, 0 destroy**;
all optional Security resources disabled). Evidence references cite the actual file and
resource. Classifications are exactly `VERIFIED_DEFECT` or `OPTIONAL_IMPROVEMENT`; a defect is
asserted only with concrete code/plan evidence.

**Summary:** 0 `VERIFIED_DEFECT`, 6 `OPTIONAL_IMPROVEMENT`. No confirmed security defect was
found in the reviewed areas. The previously identified ECS-egress gap was already corrected
(see §15) and is confirmed closed in the latest plan.

---

## 1. Fourteen required review areas

### 1. IAM least privilege — OPTIONAL_IMPROVEMENT
- **Observed:** Two distinct roles (`aws_iam_role.execution`, `aws_iam_role.task`) with a trust
  policy scoped to `ecs-tasks.amazonaws.com` plus `aws:SourceAccount` and `ArnLike aws:SourceArn`
  conditions. Execution role attaches only the AWS-managed `AmazonECSTaskExecutionRolePolicy`;
  task role carries **no** policy. No IAM user, no access key, no `AdministratorAccess`, no
  wildcard principal.
- **Evidence:** `modules/backend/iam.tf`.
- **Implication:** Strong least-privilege posture. The only note: the execution role relies on an
  AWS-managed policy; for stricter environments a hand-scoped policy could narrow ECR/Logs actions.
- **Classification:** OPTIONAL_IMPROVEMENT (managed-policy use is acceptable for DEV).

### 2. Secrets Manager permissions — OPTIONAL_IMPROVEMENT
- **Observed:** No secret value in any file; the module references an external secret only by ARN
  (`var.app_secret_arn`, `sensitive = true`, default `null`). When set, a scoped policy grants
  `secretsmanager:GetSecretValue` on **exactly** the supplied ARN(s) (`distinct(compact([...]))`),
  no wildcard resource, attached only to the execution role.
- **Evidence:** `modules/backend/secrets.tf`; `envs/dev/variables.tf` (`app_secret_arn` sensitive).
- **Implication:** Correct and minimal. Minor discrepancy: the file comment claims
  `ssm:GetParameters` is included for SSM-ARN support, but the policy action list contains only
  `secretsmanager:GetSecretValue`. This is a **stale comment**, not an over-grant (the policy is
  actually tighter than the comment implies), so it is not a defect.
- **Classification:** OPTIONAL_IMPROVEMENT (correct the stale comment; policy itself is sound).

### 3. Security-group ingress and egress — OPTIONAL_IMPROVEMENT
- **Observed (ingress):** ALB ingress only from the CloudFront origin-facing managed prefix list
  on the listener port; ECS ingress only from the ALB SG (SG-to-SG) on the container port. No
  `0.0.0.0/0` ingress anywhere.
- **Observed (egress):** `alb_to_ecs` (ALB→ECS, TCP 8000, SG-ref); `ecs_egress_https` (ECS→
  `0.0.0.0/0`, TCP 443); `ecs_egress_mongodb_atlas` (ECS→`0.0.0.0/0`, TCP 27017). No all-protocol
  (`-1`) egress. Confirmed in the plan.
- **Evidence:** `modules/backend/alb.tf`; `tfplan-dev.json` egress-rule review.
- **Implication:** Well-scoped. The two ECS egress rules use `0.0.0.0/0` because the destinations
  are many AWS regional endpoints plus external Atlas reached via NAT (no interface endpoints to
  reference). This is the conventional safe pattern for private, no-public-IP Fargate tasks and
  introduces no inbound exposure. Tightening to AWS IP-range prefix lists is a possible future
  refinement.
- **Classification:** OPTIONAL_IMPROVEMENT.

### 4. CloudFront-to-ALB restriction — (no issue)
- **Observed:** The internal ALB accepts ingress only from the CloudFront origin-facing prefix
  list; CloudFront reaches the ALB over the VPC Origin. ALB is `internal = true`.
- **Evidence:** `modules/backend/alb.tf` (`alb_from_cloudfront`, `aws_lb.app internal = true`);
  `modules/edge/cloudfront.tf` (VPC Origin).
- **Implication:** The ALB is not reachable from arbitrary CIDRs or the internet. No change needed.
- **Classification:** OPTIONAL_IMPROVEMENT — none required (recorded for completeness; no defect).

### 5. ECS private networking — (no issue)
- **Observed:** `network_configuration { subnets = private_subnet_ids, assign_public_ip = false }`.
- **Evidence:** `modules/backend/ecs.tf` (`aws_ecs_service.app`).
- **Implication:** Tasks run in private subnets with no public IP. Correct.
- **Classification:** OPTIONAL_IMPROVEMENT — none required; no defect.

### 6. MongoDB Atlas connectivity — (no issue)
- **Observed:** Atlas is external; tasks egress TCP 27017 (TLS) via the NAT Gateway's stable IP
  (output `nat_public_ip`) which is added to the Atlas IP access list. The URI is injected from
  Secrets Manager as `MONGODB_URL`; never in Terraform.
- **Evidence:** `modules/backend/alb.tf` (`ecs_egress_mongodb_atlas`); `modules/backend/ecs.tf`
  (`MONGODB_URL` secret wiring); `modules/network/natgw.tf`.
- **Implication:** Connectivity path is correct and credential-free in code.
- **Classification:** OPTIONAL_IMPROVEMENT — none required; no defect.

### 7. S3 public-access blocking — (no issue)
- **Observed:** Frontend bucket has all four BPA flags true; trail bucket (when created) likewise.
- **Evidence:** `modules/edge/s3.tf` (`aws_s3_bucket_public_access_block.frontend`);
  `modules/security/cloudtrail.tf` (`aws_s3_bucket_public_access_block.trail`).
- **Implication:** Buckets cannot be made public. Correct.
- **Classification:** OPTIONAL_IMPROVEMENT — none required; no defect.

### 8. CloudFront Origin Access Control (OAC) — (no issue)
- **Observed:** OAC with `signing_behavior = always`, `sigv4`; bucket policy grants `s3:GetObject`
  only to `cloudfront.amazonaws.com` scoped to the distribution ARN via `AWS:SourceArn`. No OAI,
  no public principal.
- **Evidence:** `modules/edge/s3.tf` (`aws_cloudfront_origin_access_control.frontend`,
  `aws_s3_bucket_policy.frontend`).
- **Implication:** Private origin access is correctly enforced with the modern mechanism.
- **Classification:** OPTIONAL_IMPROVEMENT — none required; no defect.

### 9. Encryption at rest — OPTIONAL_IMPROVEMENT
- **Observed:** SSE-S3 (AES256, AWS-managed) on the frontend bucket and the optional trail bucket.
  No customer-managed KMS key. SNS security-alerts topic has no SSE-at-rest (documented rationale:
  the AWS-managed SNS key cannot support service-to-topic encrypted publish).
- **Evidence:** `modules/edge/s3.tf`, `modules/security/cloudtrail.tf`, `modules/security/sns.tf`.
- **Implication:** AWS-managed encryption is appropriate and sufficient for DEV. A customer-managed
  KMS key (with a key policy for the EventBridge principal) would add encrypted-at-rest SNS and
  CMK-controlled S3 for a hardened environment.
- **Classification:** OPTIONAL_IMPROVEMENT (CMK deferred for cost; see §2).

### 10. Encryption in transit — (no issue)
- **Observed:** CloudFront viewer uses `redirect-to-https`; SNS delivery is TLS; Atlas is reached
  over TLS (27017). The CloudFront→ALB origin hop is HTTP over the private VPC Origin path (an
  internal, non-internet segment by design).
- **Evidence:** `modules/edge/cloudfront.tf` (`viewer_protocol_policy`); `modules/security/sns.tf`.
- **Implication:** Public/viewer and external DB traffic are encrypted. The internal HTTP hop is a
  documented DEV design choice behind the private VPC Origin.
- **Classification:** OPTIONAL_IMPROVEMENT — none required for DEV; no defect.

### 11. CloudWatch log retention — (no issue)
- **Observed:** ECS application log group `retention_in_days = var.log_retention_days` (DEV = 7);
  never unlimited.
- **Evidence:** `modules/backend/logs.tf`; `envs/dev/variables.tf` (`log_retention_days` default 7,
  validated against allowed CloudWatch values).
- **Implication:** Bounded retention controls cost; explicit, not indefinite. Correct.
- **Classification:** OPTIONAL_IMPROVEMENT — none required; no defect.

### 12. ECR image scanning — (no issue)
- **Observed:** `image_scanning_configuration { scan_on_push = true }` on the one ECR repo (basic
  scanning). Inspector enhanced scanning not enabled. Exactly one scanning config across modules.
- **Evidence:** `modules/backend/ecr.tf`; `tfplan-dev.json` (single ECR `image_scanning_configuration`).
- **Implication:** Basic scan-on-push is active; enhanced scanning deferred (billable). Correct.
- **Classification:** OPTIONAL_IMPROVEMENT — none required; no defect (enhanced deferred by design).

### 13. Sensitive Terraform outputs — OPTIONAL_IMPROVEMENT
- **Observed:** No output exposes a secret. `app_secret_arn`/`staff_admin_secret_arn` are
  `sensitive = true` inputs and are never output. Security module outputs
  (`web_acl_arn`, `security_alerts_topic_arn`, `cloudtrail_bucket_name`, `cloudtrail_trail_arn`)
  are non-secret identifiers. The DEV root does **not** re-export the security module's outputs.
- **Evidence:** `envs/dev/outputs.tf`; `modules/security/outputs.tf`; `envs/dev/variables.tf`.
- **Implication:** No secret leakage. Minor: operators cannot see the security topic/trail ARN at
  the root (only relevant once a capability is enabled); re-exporting them would improve
  operability. No sensitive value is exposed either way.
- **Classification:** OPTIONAL_IMPROVEMENT (optionally re-export non-secret security outputs).

### 14. Terraform state handling — OPTIONAL_IMPROVEMENT
- **Observed:** S3 remote backend (`backend "s3" {}` configured via `-backend-config=backend.config`)
  with `encrypt = true` and `use_lockfile = true`; state key `ecs-dev/terraform.tfstate`. No state
  file is committed; plan artifacts (`tfplan-dev`, `tfplan-dev.json`) are git-ignored (confirmed).
- **Evidence:** `envs/dev/backend.tf`; `backend.config`; `git check-ignore` on the plan artifacts.
- **Implication:** Encrypted, locked remote state with no committed state/plans. Sound. A possible
  future refinement is an explicit bucket-level state-access policy review and versioning
  confirmation (out of scope for this module).
- **Classification:** OPTIONAL_IMPROVEMENT.

---

## 2. Deferred security services

Pricing figures are approximate `us-east-1` planning estimates with stated assumptions, **not a
quote**; where pricing is usage-dependent it is marked UNCERTAIN. Recommendation for all: keep
**deferred** for cost-optimized DEV absent a documented justification.

| Service | Risk addressed | Implemented | Recommended for DEV | Est. monthly USD (assumptions) | Deferred |
| --- | --- | --- | --- | --- | --- |
| **Amazon GuardDuty** | Threat detection (malicious API/network/DNS activity) | false | false | ~$3–10/mo UNCERTAIN (usage-based on CloudTrail/VPC/DNS volume; low at DEV scale) | true |
| **AWS Config** | Resource configuration compliance/history | false | false | ~$2+/mo UNCERTAIN ($0.003 per config item + rule evaluations; grows with resource count/changes) | true |
| **AWS Security Hub** | Aggregated findings + standards checks | false | false | ~$0.0010/check + finding ingestion UNCERTAIN; commonly $10+/mo once standards enabled | true |
| **Amazon Inspector (enhanced ECR scanning)** | Deep CVE scanning of container images | false | false | ~$0.09 per image scan + rescans UNCERTAIN (per-image, per-month); basic scan-on-push already covers DEV at $0 | true |
| **Customer-managed KMS (CMK)** | Customer-controlled encryption keys / encrypted SNS at rest | false | false | ~$1/key/mo + $0.03 per 10k requests | true |

All five are **not implemented** (no resources); only default-off toggles exist for GuardDuty/
Config/Security Hub/Inspector as a future gating surface, and no CMK variable exists. **Keep all
deferred** for DEV; AWS-managed encryption and ECR basic scanning satisfy current requirements.

---

## 3. Architecture confirmations

| Condition | Result | Evidence |
| --- | --- | --- |
| ECS tasks use private subnets, no public IP | **CONFIRMED** | `modules/backend/ecs.tf`: `subnets = private_subnet_ids`, `assign_public_ip = false` |
| ALB is internal | **CONFIRMED** | `modules/backend/alb.tf`: `aws_lb.app internal = true`, private subnets |
| Frontend S3 private behind CloudFront OAC | **CONFIRMED** | `modules/edge/s3.tf`: BPA all-true + OAC SigV4 + distribution-scoped bucket policy, no public principal |
| No new public exposure introduced | **CONFIRMED** | Plan review: WAF only attaches to the existing distribution; ECS egress is outbound-only; no new ingress or public endpoint; one CloudFront distribution |

---

## 4. Preserved-settings verification

| Setting | Result | Evidence |
| --- | --- | --- |
| MongoDB Secrets Manager ARN references | **UNCHANGED** | `envs/dev/terraform.tfvars` (`app_secret_arn`, `staff_admin_secret_arn` present, same values) |
| MongoDB database names | **UNCHANGED** | `terraform.tfvars`: `teacher_student_db`, `admin_staff_mongodb` |
| Application image tag | **UNCHANGED** | `terraform.tfvars`: `image_tag = "latest"` |
| ECS `desired_count` | **UNCHANGED** | `terraform.tfvars`: `desired_count = 0` |
| ECS autoscaling `min_capacity` | **UNCHANGED** | `terraform.tfvars`: `min_capacity = 0` |
| NAT Gateway configuration | **UNCHANGED** | `terraform.tfvars`: `enable_nat_gateway = true`; `modules/network/natgw.tf` unmodified |

---

## 5. Review of existing backend changes

The approved backend security corrections were reviewed against the code and the latest plan:

| Change | Addresses a defect? | Assessment |
| --- | --- | --- |
| ALB egress restricted to ECS SG on TCP 8000 (`alb_to_ecs`) | Yes — replaced a prior unrestricted `0.0.0.0/0` ALB egress | **Justified.** Least-privilege; closed an over-broad egress. |
| ECS outbound TCP 443 to `0.0.0.0/0` (`ecs_egress_https`) | Yes — the ECS SG previously had **no** egress rule, which would block ECR/Logs/Secrets/STS at task start | **Justified.** Restores required AWS-service egress; closes the connectivity gap. |
| ECS outbound TCP 27017 to `0.0.0.0/0` (`ecs_egress_mongodb_atlas`) | Yes — same gap; Atlas unreachable without it | **Justified.** Required for the external database over NAT. |
| Secrets Manager IAM policy ARN deduplication (`distinct(...)`) | Partial — both ARN vars reference the same secret, so the list would contain duplicate ARNs | **Justified.** Avoids a duplicate resource entry in the scoped policy; no permission widening (still exactly the supplied ARN set). |

**Other backend changes:** no other IAM, security-group, Secrets Manager, or ECS networking change
was found beyond those above. No unjustified backend change was identified. The Security module
itself made **no** change to any existing Backend IAM role, security group, Secrets Manager
reference, or ECS networking setting — its only cross-module touch is the additive, optional edge
`web_acl_id` input.

---

## 6. Confirmed facts vs assumptions

- **Confirmed (from code/plan):** all 14-area observations, the four architecture confirmations,
  the six preserved settings, the egress-rule set, single CloudFront distribution, single ECR
  scanning config, encrypted/locked remote state, git-ignored plan artifacts, and the zero-
  Security-resource default posture.
- **Assumptions / uncertain:** the deferred-service monthly cost figures (usage-based; marked
  UNCERTAIN). The MongoDB Atlas connection scheme (`mongodb+srv://` → port 27017) is inferred from
  the project architecture docs and standard Atlas behavior, since the URI is secret and not in
  code; the egress rule opens 27017 on that basis.

---

## 7. VERIFIED_DEFECT findings

**None.** No reviewed area produced concrete evidence of a security defect. The previously
identified ECS-egress connectivity gap was corrected before this review and is confirmed closed in
`tfplan-dev` (three scoped egress rules present; no all-protocol egress).
