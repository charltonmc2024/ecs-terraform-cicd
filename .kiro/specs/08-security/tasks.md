# Implementation Plan: 08-security

## Overview

This plan authors a NEW reusable security module at `ecs-terraform/modules/security/` and wires it into the
existing deployment root at `ecs-terraform/envs/dev/`, alongside the already-implemented `module.network`,
`module.backend`, `module.edge`, and `module.observability`. The module owns four independently toggled,
cost-optimized capabilities, each gated by its own default-`false` boolean: an optional WAFv2 `CLOUDFRONT`
web ACL (Common Rule Set in count mode plus one rate-based rule), an optional management-events-only
CloudTrail trail with its backing S3 bucket, optional EventBridge security-event rules on the default bus,
and an optional SNS security-alerts topic. With every toggle at its default, the module creates ZERO
billable security resources (the "$0 baseline" scoped to this module's additional resources only).

Build order is bottom-up and grouped into small, independently reviewable tasks: scaffold the module
skeleton; declare all typed/validated variables; implement each capability file (`waf.tf`, `cloudtrail.tf`,
`sns.tf`, `eventbridge.tf`); add the single additive `web_acl_id` input to the edge module; implement
outputs; add the `aws.us_east_1` provider alias and wire `module "security"` plus the edge `web_acl_id` in
the dev root; then format, validate, and review a plan; then run the security + git-diff review; and finally
update documentation and produce the security-architecture review findings. The only change any existing
module receives is the ADDITIVE, optional `web_acl_id` input on the edge module (default `null`), which
leaves the distribution unchanged when WAF is off.

### CRITICAL CONSTRAINTS — this plan is CONFIGURATION AUTHORING + VALIDATION ONLY

- Tasks WRITE Terraform and run `terraform fmt`/`validate`/`plan` at most. NO task runs `terraform apply` or
  `terraform destroy`, creates/updates/deletes any AWS resource, or enables any billable AWS security
  service — every feature toggle stays at its default `false` (R13.7, R14.3, R14.4, R16.3).
- A task MAY run `terraform init`/`validate`/`plan`, but any task that triggers a `terraform init` which
  downloads providers MUST first state that initialization downloads providers (a network-dependent action)
  before execution (R13.8).
- Do NOT overwrite the existing saved `tfplan-dev` plan file (R13.7).
- No git branch/commit/push/merge/rebase/reset operation; all file changes confined to the
  `~/ecs-terraform-cicd` repository tree; no `envs/staging` or `envs/prod` (R16.1, R16.2, R16.3, R16.6).
- Preserve the MongoDB Secrets Manager ARN references (`app_secret_arn`, `staff_admin_secret_arn`), the
  MongoDB database names (`teacher_student_db`, `admin_staff_mongodb`), the ECS bootstrap values
  (`image_tag = "latest"`, `desired_count = 0`, `min_capacity = 0`), the NAT Gateway configuration, and the
  existing network/backend/edge/observability architecture UNCHANGED (R16.5).

This is declarative Terraform Infrastructure-as-Code with no runtime algorithm or data transformation, so
property-based testing does NOT apply and the design intentionally omits a Correctness Properties section.
Verification is the Terraform workflow plus plan inspection, with NO `apply` and NO `destroy`.

## Tasks

- [x] 1. Scaffold the security module skeleton
  - [x] 1.1 Create the `modules/security/` file layout with `main.tf` shared blocks
    - Create `modules/security/main.tf` with the inline `terraform {}` block: `required_version = "~> 1.16.0"`
      and a `required_providers` entry for `aws` with `source = "hashicorp/aws"` and
      `version = ">= 6.67.0, < 7.0.0"`; declare NO `backend` block and NO `provider` block
    - Add `locals { name_prefix = "${var.app_name}-${var.environment}" }` as the single location that states
      the `"${app_name}-${environment}"` expression (no restatement elsewhere in the module)
    - Add `data "aws_caller_identity" "current" {}` for account-scoping (SNS/topic/S3 policies), so no AWS
      account id is a hardcoded literal
    - Create the module file set required by the design: `waf.tf`, `cloudtrail.tf`, `eventbridge.tf`,
      `sns.tf`, `variables.tf`, `outputs.tf`; keep the `terraform {}` and `locals` blocks in `main.tf` per
      module convention and create `versions.tf` ONLY if it carries real declarations — never an empty `.tf`
      file
    - _Requirements: 1.1, 1.2, 1.3, 1.5, 1.7, 2.5_

- [x] 2. Declare all module input variables (`variables.tf`)
  - [x] 2.1 Create every typed, described, validated input with no DEV literal embedded
    - Naming / tags: `app_name` (string, non-empty/non-whitespace validation), `environment` (string,
      non-empty/non-whitespace validation), `tags` (map(string), `default = {}`) carrying the common
      `Project`/`Environment`/`ManagedBy`/`Owner` set
    - WAF: `enable_waf` (bool, `false`); `waf_default_action` (string, `"allow"`, one of `allow`/`block`);
      `waf_rate_limit` (number, `2000`, integer `>= 100 && <= 2000000000`);
      `waf_common_rule_set_mode` (string, `"Count_Mode"`, one of `Count_Mode`/`Block_Mode`);
      `waf_rate_based_rule_mode` (string, `"Count_Mode"`, one of `Count_Mode`/`Block_Mode`);
      `enable_known_bad_inputs` (bool, `false`); `waf_known_bad_inputs_mode` (string, `"Count_Mode"`, one of
      `Count_Mode`/`Block_Mode`)
    - CloudTrail: `enable_cloudtrail` (bool, `false`); `reuse_existing_trail` (bool, `false`);
      `cloudtrail_retention_days` (number, `365`, integer `>= 1 && <= 365`)
    - Alerts: `enable_security_alerts` (bool, `false`); `security_alerts_email` (string, `""` — operational
      config, not a secret)
    - Detective toggles (gating surface only, all default `false`): `enable_guardduty`, `enable_config`,
      `enable_security_hub`, `enable_inspector_enhanced`
    - Every variable has an explicit `type` and a 1–1024 char `description`; each enum/range validation
      message names the offending variable and its allowed values/range; declare NO CMK variable
    - _Requirements: 1.3, 1.4, 1.8, 3.1, 3.4, 3.5, 3.7, 3.8, 3.11, 3.12, 4.1, 4.2, 4.5, 8.1, 8.4, 8.6, 8.7, 9.1, 10.2, 11.4, 11.6, 14.3, 14.6, 14.8_

- [x] 3. Implement the optional WAFv2 web ACL (`waf.tf`)
  - [x] 3.1 Create the count-gated `aws_wafv2_web_acl.this`
    - `count = var.enable_waf ? 1 : 0`; `scope = "CLOUDFRONT"` (created through the mapped `us-east-1`
      provider); `name` and all metric names derived from `local.name_prefix` with no hardcoded name string
    - `default_action` from `var.waf_default_action` (`allow`/`block`, default `allow`)
    - Rule 1 — Common Rule Set (`priority = 1`): `managed_rule_group_statement` with
      `name = "AWSManagedRulesCommonRuleSet"`, `vendor_name = "AWS"`, `override_action` derived from
      `var.waf_common_rule_set_mode` (`Count_Mode` ⇒ `override_action { count {} }` default; `Block_Mode` ⇒
      `override_action { none {} }`)
    - Rule 2 — Rate-based rule (`priority = 2`): exactly one `rate_based_statement` with
      `limit = var.waf_rate_limit`, `aggregate_key_type = "IP"`, fixed 300-second window; action from
      `var.waf_rate_based_rule_mode` (`Count_Mode` ⇒ `action { count {} }` default; `Block_Mode` ⇒
      `action { block {} }`)
    - Rule 3 — Known-Bad-Inputs (optional, `priority = 3`): created only when
      `var.enable_known_bad_inputs = true` via `AWSManagedRulesKnownBadInputsRuleSet`, `override_action` from
      `var.waf_known_bad_inputs_mode` (default count)
    - Distinct ascending integer priorities (1, 2, 3) with no collisions; the ACL and EVERY rule set a
      `visibility_config` with `cloudwatch_metrics_enabled = true`, `sampled_requests_enabled = true`, and a
      `name_prefix`-derived metric name that is unique across rules, ≤ 128 chars, alphanumeric/hyphen/
      underscore only
    - Excluded by design: NO premium/paid managed group, NO Bot Control, NO CAPTCHA, NO Challenge action, and
      NO `aws_wafv2_web_acl_logging_configuration`; apply common tags merged with a `Name`
    - As delivered, both managed-group override and rate-rule action default to count, so matched requests are
      counted/labeled but never blocked (the only non-count disposition is `default_action = allow`)
    - _Requirements: 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 3.8, 3.9, 3.10, 3.11, 3.13, 3.14, 3.15, 4.1, 4.3, 4.4, 4.5, 5.1, 5.2, 5.3, 5.4, 5.5, 5.6_

- [x] 4. Add the optional `web_acl_id` input to the edge module and wire the distribution
  - [x] 4.1 Add the additive `web_acl_id` variable and set it on the distribution
    - Add to `modules/edge/variables.tf` a new `web_acl_id` variable: `type = string`, `default = null`, with
      a description stating `null` leaves the distribution with no web ACL association
    - In `modules/edge/cloudfront.tf`, set `web_acl_id = var.web_acl_id` on `aws_cloudfront_distribution.this`
      (one line; `null` ⇒ no association, a valid deployable distribution)
    - Change nothing else in the edge module; create/replace/duplicate NO `aws_cloudfront_distribution` (the
      total count stays exactly one, edge-owned); introduce no reference from edge to the security module
    - _Requirements: 6.3, 6.4, 6.5, 6.6_

- [x] 5. Implement the reuse-first optional CloudTrail trail (`cloudtrail.tf`)
  - [x] 5.1 Create the count-gated management-events trail, bucket, and REQUIRED bucket policy
    - Gate every resource by `enable_cloudtrail && !reuse_existing_trail` (reuse decision from the operator's
      coverage + `IsLogging = true` check recorded in `var.reuse_existing_trail`)
    - `aws_cloudtrail.this`: management events only (`include_management_events = true`,
      `read_write_type = "All"`), `enable_log_file_validation = true`; NO data-event selectors, NO CloudTrail
      Lake, NO CloudWatch Logs delivery
    - `aws_s3_bucket.trail` named from `local.name_prefix`; `aws_s3_bucket_public_access_block.trail` with all
      four settings `true`; `aws_s3_bucket_server_side_encryption_configuration.trail` with SSE-S3 (`AES256`,
      AWS-managed) — NO CMK
    - REQUIRED `aws_s3_bucket_policy.trail` allowing `cloudtrail.amazonaws.com`: `s3:GetBucketAcl` on the
      bucket ARN and `s3:PutObject` on `AWSLogs/<account-id>/*` with a `StringEquals` condition on
      `s3:x-amz-acl = "bucket-owner-full-control"`; both statements additionally scoped by `aws:SourceArn`
      (trail ARN) and `aws:SourceAccount` (current account) sourced from `data.aws_caller_identity.current`
      so no account id, bucket ARN, or trail ARN is a hardcoded literal
    - `aws_s3_bucket_lifecycle_configuration.trail` expiring trail objects after
      `var.cloudtrail_retention_days` (≤ 365) so nothing is retained indefinitely; apply common tags
    - _Requirements: 8.1, 8.2, 8.5, 8.6, 8.7, 8.8, 8.9, 1.7_

- [x] 6. Implement the SNS security-alerts topic (`sns.tf`)
  - [x] 6.1 Create the count-gated topic, topic policy, and optional email subscription
    - `aws_sns_topic.security_alerts`: `count = var.enable_security_alerts ? 1 : 0`, named
      `"${local.name_prefix}-security-alerts"`; NO server-side encryption at rest (TLS in transit only, per
      the documented EventBridge-publish reason); common tags applied
    - `aws_sns_topic_policy.security_alerts` from an `aws_iam_policy_document` allowing
      `events.amazonaws.com` to `SNS:Publish` on this topic, scoped by an `aws:SourceAccount` condition from
      `data.aws_caller_identity.current` — no hardcoded account id; present whenever the topic is (hard
      dependency of the EventBridge targets)
    - `aws_sns_topic_subscription.security_alerts_email`:
      `count = var.enable_security_alerts && trimspace(var.security_alerts_email) != "" ? 1 : 0`,
      protocol `email`, endpoint `var.security_alerts_email` (empty email ⇒ topic exists with no subscription)
    - Create NO Lambda or custom processor
    - _Requirements: 9.2, 10.1, 10.3, 10.4, 10.5, 10.6, 10.7_

- [x] 7. Implement the EventBridge security-event rules (`eventbridge.tf`)
  - [x] 7.1 Create the count-gated narrow rules and SNS targets
    - Count-gated by `enable_security_alerts`; one narrow `aws_cloudwatch_event_rule` per concern on the
      DEFAULT bus with `detail-type = "AWS API Call via CloudTrail"` and specific `detail.eventSource` +
      `detail.eventName` patterns (never a catch-all):
      - IAM policy changes (`iam.amazonaws.com`): Put/Attach/Detach User/Group/Role policy, Create/Delete
        Policy, Create/Delete PolicyVersion
      - Security-group ingress/egress (`ec2.amazonaws.com`): Authorize/Revoke Security Group Ingress/Egress
      - CloudTrail config changes (`cloudtrail.amazonaws.com`): `StopLogging`, `UpdateTrail`, `DeleteTrail`
    - One `aws_cloudwatch_event_target` per rule whose `arn` is the SNS security-alerts topic; depends on the
      `aws_sns_topic_policy.security_alerts` (hard dependency — without it EventBridge cannot publish)
    - Create NO Lambda or other custom event-processing service; document that these rules only match when a
      suitable ACTIVE trail (reused existing with `IsLogging = true`, or the enabled `Optional_Trail`)
      delivers API-call events to the default bus
    - _Requirements: 9.2, 9.3, 9.4, 9.5, 9.6, 9.7, 8.9_

- [x] 8. Implement module outputs (`outputs.tf`)
  - [x] 8.1 Create the minimal consumed outputs, each null-safe when its feature is off
    - `web_acl_arn = var.enable_waf ? one(aws_wafv2_web_acl.this[*].arn) : null` (non-empty `arn:` string when
      WAF enabled; `null` when disabled) — consumed by the dev root to wire the edge `web_acl_id`
    - `security_alerts_topic_arn = one(aws_sns_topic.security_alerts[*].arn)` (null when alerts disabled)
    - `cloudtrail_bucket_name = one(aws_s3_bucket.trail[*].bucket)` (null unless a new trail is created)
    - Expose no other output and no secret-derived value
    - _Requirements: 6.1, 6.2_

- [x] 9. Add the us-east-1 provider alias and wire the module in the dev root
  - [x] 9.1 Declare the `aws.us_east_1` provider alias in `envs/dev/providers.tf`
    - Add `provider "aws" { alias = "us_east_1", region = "us-east-1" }` carrying the IDENTICAL `default_tags`
      common-tag set (same keys and values: `Project`/`Environment`/`ManagedBy`/`Owner`) used by the
      default-region provider; leave the default-region provider unchanged; place no credentials in the block
    - The alias is declared even while `enable_waf = false`, so enabling WAF later needs no extra wiring
    - _Requirements: 2.1, 2.6, 2.7_

  - [x] 9.2 Declare the root-level security variables and DEV tfvars values
    - Add to `envs/dev/variables.tf` with explicit types and descriptions: `enable_waf` (bool, default
      `false`), `enable_cloudtrail` (bool, default `false`), `enable_security_alerts` (bool, default
      `false`), `security_alerts_email` (string, default `""`)
    - Set DEV values in `envs/dev/terraform.tfvars`: all toggles `false`, `security_alerts_email = ""`; place
      NO secret in tfvars; leave the preserved MongoDB/ECS/NAT bootstrap values unchanged
    - _Requirements: 14.3, 16.5_

  - [x] 9.3 Add the `module "security"` block and wire the edge `web_acl_id` in `envs/dev/main.tf`
    - `source = "../../modules/security"` with `providers = { aws = aws.us_east_1 }`; pass `app_name`,
      `environment`, the common `tags` map, `enable_waf = var.enable_waf`,
      `enable_cloudtrail = var.enable_cloudtrail`, `enable_security_alerts = var.enable_security_alerts`,
      `security_alerts_email = var.security_alerts_email`; WAF tuning / detective toggles use module defaults
    - Set `web_acl_id = module.security.web_acl_arn` on the existing `module "edge"` block (null while WAF
      off) through module-output references only; preserve the existing `module "network"`,
      `module "backend"`, `module "edge"`, `module "observability"` blocks and the `network → backend → edge`
      direction with no circular dependency
    - _Requirements: 2.2, 2.3, 6.6, 6.7_

- [x] 10. Checkpoint - module self-contained and additive
  - Confirm `modules/security` parses with `main.tf`, `waf.tf`, `cloudtrail.tf`, `eventbridge.tf`, `sns.tf`,
    `variables.tf`, `outputs.tf`; no empty `.tf` file; no `provider`/`backend` block; every capability
    count-gated to `0` at defaults; outputs null-safe; the only existing-module change is the additive edge
    `web_acl_id`; preserved MongoDB/ECS/NAT bootstrap values untouched. Ensure parsing is clean; ask the user
    if questions arise.

- [x] 11. Format the module and dev root (`terraform fmt`)
  - [x] 11.1 Run `terraform fmt -recursive` and confirm a clean check
    - Run `terraform fmt -recursive`, then confirm `terraform fmt -check -recursive` exits 0 with zero files
      requiring formatting over `modules/security`, `modules/edge`, and `envs/dev`
    - _Requirements: 13.1_

- [x] 12. Validate the dev root (`terraform validate`, no apply)
  - [x] 12.1 Initialize and validate, resolving every error before planning
    - STATE FIRST that `terraform init` downloads providers (a network-dependent action) before running it;
      then run `terraform init` and `terraform validate` from `envs/dev`
    - Confirm `terraform validate` exits 0 with zero errors; if any error is reported, resolve it and re-run
      until it exits 0 before proceeding to planning; a type-less variable or a bad enum/range input fails
      validation naming the offending variable
    - Confirm the resolved AWS provider satisfies `>= 6.67.0, < 7.0.0` (lock resolves `6.67.0`) and supports
      WAFv2 `CLOUDFRONT` scope through the `us-east-1` alias; halt and report if incompatible
    - _Requirements: 13.2, 13.3, 13.4, 13.8_

- [x] 13. Review the default DEV plan (no apply, do not overwrite tfplan-dev)
  - [x] 13.1 Confirm the zero-security-resource baseline and non-duplication invariants
    - Run `terraform plan` from `envs/dev` with all toggles at their DEV defaults (off); do NOT write to or
      overwrite the saved `tfplan-dev` plan file
    - Confirm ZERO security resources planned: no `aws_wafv2_web_acl`, no `aws_cloudtrail` / trail bucket /
      bucket policy / lifecycle, no `aws_cloudwatch_event_rule` / `aws_cloudwatch_event_target`, no
      `aws_sns_topic`; `web_acl_arn` plans as `null` and the distribution has no web ACL association
    - Confirm exactly ONE `aws_cloudfront_distribution` (edge-owned) and exactly ONE ECR
      `image_scanning_configuration` (backend-owned) across all modules; the module duplicates no
      network/backend/edge/observability resource; report the specific duplicate and halt if any is found
    - Confirm no `terraform apply` is run and no AWS resource is created
    - _Requirements: 13.5, 13.7, 3.2, 6.2, 6.3, 7.1, 7.2_

  - [ ] 13.2* Optional toggles-on plan sanity check, then revert to off
    - With `enable_waf`, `enable_cloudtrail`, and `enable_security_alerts` set `true` and a dummy
      `security_alerts_email`, run `terraform plan` (still plan only, NO apply) and confirm the expected
      resources appear: one WAFv2 web ACL (Common Rule Set count + one rate rule) with per-rule visibility;
      one trail + bucket with BPA/SSE/policy/lifecycle; the EventBridge rules + targets; one SNS topic + email
      subscription
    - Revert all toggles to `false` and the email to `""` afterward; do NOT overwrite `tfplan-dev`; run no
      `apply`
    - _Requirements: 13.5, 13.7_

- [x] 14. Security and git-diff review (no commit, no push)
  - [x] 14.1 Scan the git diff for secrets and confirm scope discipline
    - Review the `git diff` of all tracked files and confirm ZERO secret values (AWS access/secret keys,
      connection URIs, tokens, passwords, private keys) are introduced; report the file and halt if any is
      found
    - Confirm no `terraform apply`/`destroy` was run, no git branch/commit/push/merge/rebase/reset, all
      changes confined to `~/ecs-terraform-cicd`, and no `envs/staging` or `envs/prod` created
    - Confirm the preserved bootstrap values (MongoDB secret ARNs, DB names, `image_tag = latest`,
      `desired_count = 0`, `min_capacity = 0`, NAT config) and the network/backend/edge/observability
      architecture are unchanged
    - _Requirements: 13.6, 13.7, 16.1, 16.2, 16.3, 16.4, 16.5, 16.6, 16.7_

- [x] 15. Update the security documentation (security topic only)
  - [x] 15.1 Document the security module architecture, posture, cost, and future hardening
    - Describe the Security_Module architecture, its position in `network → backend → edge`, the module that
      owns the CloudFront web ACL, and how the optional web ACL attaches via the edge `web_acl_id` input
    - List each WAF rule by name, its starting mode (all `Count_Mode`), which rules are intended to move to
      `Block_Mode`, and the measurable zero-false-positive condition over a defined observation window (e.g.
      7 days of DEV traffic) before transition
    - State the ECR scanning posture (basic `scan_on_push` retained, Inspector enhanced scanning deferred;
      repository-level/no-extra-charge vs account-level/billable) and the Jenkins scan-finding gate including
      the severity threshold at which the stage fails and the 300-second results-unavailable failure
    - Describe the CloudTrail reuse-first strategy and Event-History limits, the EventBridge active-trail
      dependency, the security-event flow through SNS, and the email subscription-confirmation step
    - State the `enable_waf`/`enable_cloudtrail`/`enable_security_alerts` default-`false` toggles and the
      $0-baseline meaning; give the estimated monthly cost and cost dimensions, the cost controls applied,
      the security validation procedures used, and the future production-hardening steps
    - Do NOT modify content outside the security topic; retain unrelated documentation unchanged
    - _Requirements: 7.4, 7.5, 7.6, 10.8, 14.1, 14.2, 14.5, 15.1, 15.2, 15.3, 15.4, 15.5, 15.6, 15.7, 15.8, 15.9_

- [x] 16. Produce the security-architecture review findings
  - [x] 16.1 Write the VERIFIED_DEFECT vs OPTIONAL_IMPROVEMENT findings and confirmations
    - Produce a written finding for each required review area (IAM least privilege, Secrets Manager
      permissions, security-group ingress/egress, CloudFront-to-ALB restriction, ECS private networking,
      MongoDB Atlas connectivity, S3 public-access blocking, CloudFront OAC, encryption at rest, encryption in
      transit, CloudWatch log retention, ECR image scanning, sensitive Terraform outputs, Terraform state
      handling), each labeled exactly one of {VERIFIED_DEFECT, OPTIONAL_IMPROVEMENT}; for each
      VERIFIED_DEFECT record the review area, observed condition, and justification
    - Evaluate GuardDuty, AWS Config, Security Hub, Amazon Inspector enhanced scanning, and customer-managed
      KMS — for each: security risk addressed, already-implemented (true/false), recommended-for-DEV
      (true/false), estimated monthly cost (USD), deferred (true/false); recommend each stays deferred for DEV
      absent a stated justification; flag any missing attribute as incomplete
    - Record CONFIRMED/NOT_CONFIRMED for: ECS tasks private with no public IP, ALB internal, frontend S3
      private behind OAC, and no public exposure introduced
    - Record UNCHANGED/CHANGED for: MongoDB Secrets Manager ARN references, MongoDB database names,
      application image tag, ECS `desired_count`, ECS autoscaling `min_capacity`, and the NAT Gateway
      configuration (confirm UNCHANGED)
    - Confirm no existing backend IAM role, security group, Secrets Manager reference, or ECS networking
      setting is modified absent a VERIFIED_DEFECT justifying the change
    - _Requirements: 11.1, 11.2, 11.3, 11.5, 11.6, 11.7, 12.1, 12.2, 12.3, 12.4, 12.5, 12.6_

- [x] 17. Final checkpoint - validation and review complete, no deployment
  - Present the formatted/validated config, the default-DEV zero-security-resource plan review, the secret +
    git-diff scan result, the documentation update, and the security-architecture review findings. Confirm
    the task STOPS at validation/planning: no `terraform apply`, no `terraform destroy`, no AWS resource
    created, no billable toggle enabled, no commit/push. Applying is OUT OF SCOPE and gated on explicit
    operator confirmation — ask the user before any `terraform apply`.

## Notes

- Tasks marked with `*` are optional and can be skipped; the plan contains exactly one optional sub-task
  (13.2, the toggles-on plan sanity check), which stays plan-only and reverts toggles to `false` afterward.
- DEV-only scope. This plan creates no `envs/staging` or `envs/prod` and no staging/production resources. The
  module stays environment-independent: typed/validated variables with no DEV literals inside the module; DEV
  values are supplied through `envs/dev/terraform.tfvars`.
- Configuration authoring + validation ONLY. No task runs `terraform apply`/`destroy`, creates/updates/
  deletes any AWS resource, enables any billable toggle (all stay default `false`), overwrites `tfplan-dev`,
  or performs any git commit/push; all changes stay within `~/ecs-terraform-cicd`.
- Before any `terraform init` that downloads providers, the plan states that initialization downloads
  providers (a network-dependent action) — see task 12.1.
- This is declarative Terraform IaC with no runtime algorithm or data transformation, so there are NO
  property-based-testing tasks; the design intentionally omits a Correctness Properties section. Verification
  is `terraform fmt`/`validate`/`plan` plus plan review.
- Non-duplication: the module creates no second CloudFront distribution (exactly one, edge-owned), no
  duplicate ECR `image_scanning_configuration` (backend-owned), and no duplicate network/backend/edge/
  observability resource. The only existing-module change is the additive, optional edge `web_acl_id` input
  (default `null`).
- Cost-optimized DEV: all three billable toggles (`enable_waf`, `enable_cloudtrail`, `enable_security_alerts`)
  and the detective toggles default `false`, so the module's additional baseline cost is $0; WAF managed
  groups and the rate rule start in count mode. No CMK is created.
- Preserved bootstrap values (MongoDB secret ARNs `app_secret_arn`/`staff_admin_secret_arn`, DB names
  `teacher_student_db`/`admin_staff_mongodb`, `image_tag = latest`, `desired_count = 0`, `min_capacity = 0`,
  NAT Gateway config) and the existing network/backend/edge/observability architecture remain unchanged.
- Applying to shared dev infrastructure is OUT OF SCOPE for this spec and gated on explicit operator
  confirmation; this plan does NOT auto-apply.

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1"] },
    { "id": 1, "tasks": ["2.1", "4.1"] },
    { "id": 2, "tasks": ["3.1", "5.1", "6.1", "8.1"] },
    { "id": 3, "tasks": ["7.1"] },
    { "id": 4, "tasks": ["9.1", "9.2", "9.3"] },
    { "id": 5, "tasks": ["11.1"] },
    { "id": 6, "tasks": ["12.1"] },
    { "id": 7, "tasks": ["13.1"] },
    { "id": 8, "tasks": ["13.2", "14.1"] },
    { "id": 9, "tasks": ["15.1", "16.1"] }
  ]
}
```
