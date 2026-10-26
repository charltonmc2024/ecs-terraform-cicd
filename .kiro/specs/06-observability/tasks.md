# Implementation Plan: 06-observability

## Overview

This plan builds a NEW reusable observability module at `ecs-terraform/modules/observability/` and wires it
into the existing deployment root at `ecs-terraform/envs/dev/`, alongside the already-implemented
`module.network`, `module.backend`, and `module.edge`. The module is purely observational: it OWNS only
CloudWatch metric alarms, a single CloudWatch dashboard, and an optional default-off SNS notification path.
It creates NO ECS, ALB, ECR, S3, CloudFront, VPC, subnet, route table, NAT gateway, internet gateway, VPC
endpoint, or security-group resource, and it declares NO ECS application log group and NO autoscaling
policy — those stay owned by the backend module.

One small, additive, non-breaking change is made to the backend module first: three new outputs
(`alb_arn_suffix`, `target_group_arn_suffix`, `ecs_log_group_name`) that expose the CloudWatch dimension
values and the backend-owned ECS log group name the observability module consumes. These are plain
references to existing resource attributes (`aws_lb.app.arn_suffix`, `aws_lb_target_group.app.arn_suffix`,
`aws_cloudwatch_log_group.app.name`); every pre-existing backend output is unchanged, no resource changes,
and the backend gains NO reference to observability. Dependency direction stays one-way
`network → backend → edge`, with observability positioned strictly as a downstream consumer; there is no
cycle.

Build order is bottom-up and grouped into small, independently reviewable tasks: additive backend outputs
first; then the module foundation (typed/validated variables plus the `terraform {}` and
`locals { name_prefix }` blocks inside the primary resource file); then the six alarms; then the dashboard;
then the optional SNS path and the `local.alarm_actions` gate; then the minimized module outputs; then the
dev-root wiring (including setting the backend's `log_retention_days = 7` for the 7-day DEV retention
target); and finally local formatting, validation, and plan-JSON inspection. The CloudFront VPC Origin edge
architecture is NOT modified — observability is additive and observe-only.

This is Terraform IaC with no runtime algorithm or data transformation, so property-based testing does NOT
apply. Verification uses `terraform fmt`/`validate`/`plan` and plan-JSON invariant assertions. Because the
real remote-state bucket has been deleted, validation is done locally without the live backend
(`terraform init -backend=false`, plugin-only) — this plan does NOT modify real state and does NOT run
`terraform apply`.

## Tasks

- [ ] 1. Add additive ALB-dimension and log-group outputs to the backend module
  - [ ] 1.1 Append `alb_arn_suffix`, `target_group_arn_suffix`, and `ecs_log_group_name` to `modules/backend/outputs.tf`
    - `alb_arn_suffix` = `aws_lb.app.arn_suffix` (CloudWatch `LoadBalancer` dimension `app/<name>/<id>`); non-empty description
    - `target_group_arn_suffix` = `aws_lb_target_group.app.arn_suffix` (CloudWatch `TargetGroup` dimension `targetgroup/<name>/<id>`); non-empty description
    - `ecs_log_group_name` = `aws_cloudwatch_log_group.app.name` (the backend-owned ECS app log group `${name_prefix}-app`, consumed not recreated); non-empty description
    - Additive ONLY: leave `ecr_repository_url`, `alb_dns_name`, `alb_arn`, `ecs_cluster_name`, `ecs_service_name` unchanged in name and value; add no resource and change no behavior
    - The backend gains NO reference to the observability module; direction stays `backend → (outputs) → observability`
    - _Requirements: 11.1, 11.2, 11.3, 11.4, 11.5, 11.6_

- [ ] 2. Build the observability module foundation (variables, version pin, locals)
  - [ ] 2.1 Create `modules/observability/variables.tf` with all typed, described, validated inputs
    - Naming: `app_name` (string, validation `^[a-z][a-z0-9-]{1,30}[a-z0-9]$`), `environment` (string, one of `dev|staging|prod`)
    - `tags` (map(string), `default = {}`) carrying the common `Project`/`Environment`/`ManagedBy`/`Owner` set
    - Consumed dimensions: `ecs_cluster_name`, `ecs_service_name`, `alb_arn_suffix`, `target_group_arn_suffix` (string, non-empty validation)
    - `ecs_log_group_name` (string) with validation rejecting an empty OR null value (consumed only, never recreated)
    - `cloudfront_distribution_id` (string, `default = null`) and `enable_cloudfront_widgets` (bool, `default = false`)
    - ECS alarms: `cpu_alarm_threshold` (number, default 80, `>= 0 && <= 100`), `memory_alarm_threshold` (number, default 80, `>= 0 && <= 100`), `ecs_alarm_period` (number, default 60, CloudWatch-valid), `ecs_alarm_evaluation_periods` (number, default 3, `>= 1 && <= 5`)
    - Unhealthy host: `unhealthy_host_threshold` (default 1, `>= 1 && <= 100`), `unhealthy_host_period` (default 60, CloudWatch-valid 60–86400), `unhealthy_host_evaluation_periods` (default 2, `>= 1 && <= 100`)
    - Target 5xx: `target_5xx_threshold` (default 5, `>= 1 && <= 100000`), `target_5xx_period` (default 300, CloudWatch-valid), `target_5xx_evaluation_periods` (default 2, `>= 1 && <= 100`)
    - ELB 5xx: `elb_5xx_threshold` (default 5, `>= 1`), `elb_5xx_period` (default 300, CloudWatch-valid), `elb_5xx_evaluation_periods` (default 2, `>= 1 && <= 100`)
    - Latency: `latency_alarm_statistic` (string, default `"p95"`, one of `p90|p95|p99`), `latency_threshold_seconds` (number, default 2, `>= 0`), `latency_alarm_period` (default 60, CloudWatch-valid), `latency_alarm_evaluation_periods` (default 3, `>= 1 && <= 100`)
    - SNS: `enable_sns` (bool, `default = false`), `sns_notification_email` (string, `default = ""`, no hardcoded endpoint)
    - No DEV literal embedded in a resource; every validation error names the offending variable and its permitted range; no secret-bearing variable (nothing references the MongoDB URI)
    - _Requirements: 1.2, 1.3, 1.4, 3.2, 3.3, 10.1, 10.2, 10.4, 10.5, 13.3, 13.6_

  - [ ] 2.2 Add the `terraform {}` required-providers block and `locals { name_prefix }` at the top of `modules/observability/cloudwatch_alarms.tf`
    - Pin `required_version` and the AWS provider consistent with the sibling modules; comment why the block lives in the primary resource file (no organizational-only `versions.tf`)
    - `name_prefix = "${var.app_name}-${var.environment}"`; comment why it lives here (no `locals.tf`)
    - Declare NO `backend` block and NO `provider` block — inherit the default AWS provider from `envs/dev/providers.tf`
    - _Requirements: 1.1, 1.5, 1.2_

- [ ] 3. Implement the ECS CPU and memory alarms (`cloudwatch_alarms.tf`)
  - [ ] 3.1 Create `CPU_Alarm` and `Memory_Alarm`
    - Two `aws_cloudwatch_metric_alarm` resources, namespace `AWS/ECS`, statistic `Average`
    - `CPU_Alarm` metric `CPUUtilization`; `Memory_Alarm` metric `MemoryUtilization`; both dimensioned by `ClusterName` (from `var.ecs_cluster_name`) and `ServiceName` (from `var.ecs_service_name`) — no hardcoded dimension strings
    - `comparison_operator = "GreaterThanOrEqualToThreshold"`; `treat_missing_data = "notBreaching"` (explicitly handles `desired_count = 0` bootstrap and low-traffic DEV)
    - `threshold`, `period`, `evaluation_periods` from `var.cpu_alarm_threshold`/`var.memory_alarm_threshold`, `var.ecs_alarm_period`, `var.ecs_alarm_evaluation_periods` (no literals)
    - `alarm_actions = local.alarm_actions`; common tags merged with a resource-specific `Name`
    - Notification/visibility only: create NO autoscaling policy or scalable target and do not touch the backend's target-tracking policy
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 1.8, 10.1, 10.6_

- [ ] 4. Implement the ALB and latency alarms (`cloudwatch_alarms.tf`)
  - [ ] 4.1 Create `Unhealthy_Host_Alarm`, `Target_5xx_Alarm`, and `ELB_5xx_Alarm`
    - `Unhealthy_Host_Alarm`: namespace `AWS/ApplicationELB`, metric `UnHealthyHostCount`, statistic `Maximum`, dimensioned by `TargetGroup` (from `var.target_group_arn_suffix`) and `LoadBalancer` (from `var.alb_arn_suffix`); threshold/period/eval from `var.unhealthy_host_*`
    - `Target_5xx_Alarm`: metric `HTTPCode_Target_5XX_Count`, statistic `Sum`, dimensioned by `TargetGroup` and `LoadBalancer`; threshold/period/eval from `var.target_5xx_*`
    - `ELB_5xx_Alarm`: metric `HTTPCode_ELB_5XX_Count`, statistic `Sum`, dimensioned by `LoadBalancer` ONLY (no `TargetGroup` dimension); threshold/period/eval from `var.elb_5xx_*`; declared as a resource distinct from `Target_5xx_Alarm`
    - All three: `comparison_operator = "GreaterThanOrEqualToThreshold"`, `treat_missing_data = "notBreaching"`, `alarm_actions = local.alarm_actions`, common tags + `Name`; dimensions only from the backend ARN-suffix inputs (no hardcoding)
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 6.1, 6.2, 6.3, 6.4, 6.5, 7.1, 7.2, 7.3, 7.4, 7.5, 10.1_

  - [ ] 4.2 Create `Latency_Alarm`
    - `aws_cloudwatch_metric_alarm` on `TargetResponseTime` (namespace `AWS/ApplicationELB`, seconds), extended-percentile statistic from `var.latency_alarm_statistic` (default `p95`)
    - Dimensioned by `TargetGroup` (from `var.target_group_arn_suffix`) and `LoadBalancer` (from `var.alb_arn_suffix`) — no hardcoding
    - `comparison_operator = "GreaterThanOrEqualToThreshold"` against `var.latency_threshold_seconds`; `period`/`evaluation_periods` from `var.latency_alarm_period`/`var.latency_alarm_evaluation_periods`
    - `treat_missing_data = "notBreaching"`; `alarm_actions = local.alarm_actions`; common tags + `Name`
    - _Requirements: 14.1, 14.2, 14.3, 14.4, 14.5, 14.6, 14.7, 10.1_

- [ ] 5. Implement the CloudWatch dashboard (`dashboard.tf`)
  - [ ] 5.1 Create the single `aws_cloudwatch_dashboard`
    - Exactly one dashboard named from `local.name_prefix`; create no second dashboard
    - ECS widgets: `CPUUtilization` and `MemoryUtilization`, each dimensioned by `ClusterName` + `ServiceName`
    - ALB widgets: `RequestCount`, `HTTPCode_Target_5XX_Count`, `HTTPCode_ELB_5XX_Count`, `HealthyHostCount`, and `TargetResponseTime` latency, each dimensioned by the `LoadBalancer` suffix and, where applicable, the `TargetGroup` suffix
    - Optional CloudFront widgets (request count + error rate from `AWS/CloudFront`) gated by `var.enable_cloudfront_widgets`; when enabled each widget pins its metric `region` to `us-east-1` and sources the distribution id from `var.cloudfront_distribution_id`; when disabled the dashboard has ECS + ALB widgets only and no `AWS/CloudFront` widget
    - Build the body with `jsonencode`; every dimension value from inputs/references — no hardcoded dimension string literal
    - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5, 8.6_

- [ ] 6. Implement the optional SNS notification path (`sns.tf`)
  - [ ] 6.1 Create the count-gated SNS topic, optional subscription, and `local.alarm_actions`
    - `aws_sns_topic` with `count = var.enable_sns ? 1 : 0`; AWS-managed encryption `kms_master_key_id = "alias/aws/sns"` (no customer-managed KMS key)
    - `aws_sns_topic_subscription` (protocol `email`) with `count = var.enable_sns && var.sns_notification_email != "" ? 1 : 0`, endpoint `var.sns_notification_email`
    - `locals { alarm_actions = var.enable_sns ? [aws_sns_topic.alarms[0].arn] : [] }`
    - Default off: with `enable_sns = false`, zero `aws_sns_topic` and zero `aws_sns_topic_subscription` exist and `alarm_actions = []`; with `enable_sns = true` and empty email, the topic exists with zero subscriptions
    - No secret value in source; common tags on the topic
    - _Requirements: 9.1, 9.2, 9.3, 9.4, 9.5, 9.6, 13.5_

- [ ] 7. Implement module outputs (`outputs.tf`)
  - [ ] 7.1 Create `modules/observability/outputs.tf`
    - `dashboard_name` = `aws_cloudwatch_dashboard.main.dashboard_name` (non-empty description)
    - `sns_topic_arn` = `var.enable_sns ? aws_sns_topic.alarms[0].arn : null` (resolves to null when disabled, no Terraform error)
    - Expose no other output and no secret-derived value
    - _Requirements: 12.5, 12.6, 13.4_

- [ ] 8. Checkpoint - module self-contained
  - Confirm `modules/observability` parses on its own with the `cloudwatch_alarms.tf`, `dashboard.tf`, `sns.tf`, `variables.tf`, `outputs.tf` files; no `provider`/`backend` block; zero application resources (no ECS/ALB/ECR/S3/CloudFront/VPC/security-group); no `aws_cloudwatch_log_group`; no autoscaling policy or scalable target; six alarms + one dashboard; dimensions only from inputs; and no undefined references. Ask the user if questions arise.

- [ ] 9. Wire the observability module into the dev root
  - [ ] 9.1 Declare the root-level observability variables and DEV tfvars values
    - Add `enable_observability_sns` (bool, default false) and `observability_sns_email` (string, default "") to `envs/dev/variables.tf` with explicit types and descriptions, plus any threshold/period overrides the root chooses to expose
    - Set DEV values in `envs/dev/terraform.tfvars`: `enable_observability_sns = false`, `observability_sns_email = ""`; place NO secret value in tfvars
    - _Requirements: 12.4, 12.7_

  - [ ] 9.2 Add the `module "observability"` block to `envs/dev/main.tf`
    - `source = "../../modules/observability"`
    - `ecs_cluster_name = module.backend.ecs_cluster_name`, `ecs_service_name = module.backend.ecs_service_name`, `alb_arn_suffix = module.backend.alb_arn_suffix`, `target_group_arn_suffix = module.backend.target_group_arn_suffix`, `ecs_log_group_name = module.backend.ecs_log_group_name`, `cloudfront_distribution_id = module.edge.cloudfront_distribution_id` — every identifier from a module output, never a literal
    - Pass `app_name`, `environment`, the common `tags` map, `enable_sns = var.enable_observability_sns`, `sns_notification_email = var.observability_sns_email`
    - Preserve the existing `module "network"`, `module "backend"`, `module "edge"` blocks; the CloudFront VPC Origin edge architecture is NOT modified (observability is observe-only)
    - _Requirements: 12.1, 12.2, 12.3, 2.3_

  - [ ] 9.3 Set the backend ECS log group retention to 7 days for DEV
    - Via the dev root, set the backend module's `log_retention_days = 7` (pass `log_retention_days = 7` into `module.backend` in `envs/dev/main.tf`, or set it in `terraform.tfvars` if the root exposes it)
    - This reduces the current 14-day backend default to 7 days for DEV only; the ECS application log group stays owned by the backend module (observability recreates nothing)
    - _Requirements: 3.4, 10.3_

  - [ ] 9.4 Re-export the two observability outputs in `envs/dev/outputs.tf`
    - Re-export exactly `observability_dashboard_name = module.observability.dashboard_name` and `observability_sns_topic_arn = module.observability.sns_topic_arn`; re-export no other observability output
    - The re-exported SNS topic ARN resolves to null while `enable_observability_sns = false` without a Terraform error; keep existing network/backend/edge outputs
    - _Requirements: 12.5, 12.6_

- [ ] 10. Format and validate (no apply)
  - [ ] 10.1 Format the module and dev root
    - Run `terraform fmt -recursive`, then `terraform fmt -check -recursive` over `modules/observability`, `modules/backend`, and `envs/dev` (zero diff)
    - _Requirements: 1.3_

  - [ ] 10.2 Validate the dev root locally without the live backend
    - Because the real remote-state bucket is deleted, run `terraform init -backend=false` (plugin-only, isolated) then `terraform validate` on the dev root; do NOT modify real state and do NOT apply
    - A bad numeric input or an empty/null `ecs_log_group_name` fails validation with a message naming the variable
    - _Requirements: 1.4, 3.3, 10.4_

- [ ] 11. Plan verification via plan-JSON inspection (no apply)
  - [ ] 11.1 Assert the DEV default and non-duplication invariants
    - With `enable_sns = false`: plan-JSON shows the SIX alarms (CPU, memory, unhealthy host, target 5xx, ELB 5xx, latency) and exactly ONE dashboard planned; zero `aws_sns_topic` and zero `aws_sns_topic_subscription`; every alarm `alarm_actions = []`
    - Plan-JSON shows the module plans NO `aws_cloudwatch_log_group` for ECS app logs and NO autoscaling policy or scalable target
    - All CloudWatch dimension values resolve from module inputs/outputs (ARN-suffix outputs) — no hardcoded ARNs, account IDs, resource names, or dimension strings
    - Additive backend outputs show 0 to change / 0 to destroy attributable to the output change; pre-existing backend outputs unchanged
    - `terraform validate`/`plan` report no dependency cycle and preserve `network → backend → edge`; observability creates no application resource
    - Confirm the task STOPS at validation/plan — no `terraform apply`, no AWS resource creation
    - _Requirements: 2.1, 2.5, 2.6, 3.1, 4.5, 9.2, 11.5, 1.7, 1.8_

- [ ] 12. Final checkpoint - operator plan review
  - Present the reviewed plan and invariant assertions. Confirm the SNS-enabled path on request (one topic, one email subscription, every alarm referencing that topic ARN) is a separate review and not applied here. Applying is out of scope for this spec and gated on explicit operator confirmation — do NOT auto-apply. Ask the user before any `terraform apply`.

## Notes

- DEV-only scope. This spec creates no `envs/staging` or `envs/prod` and no staging/production resources.
  The module stays environment-independent: typed/validated variables with no DEV literals inside the
  module; DEV values are supplied through `envs/dev/terraform.tfvars`.
- This is declarative Terraform IaC with no runtime algorithm or data transformation, so there are NO
  property-based-testing tasks. Verification is `terraform fmt`/`validate`/`plan` plus plan-JSON inspection,
  consistent with the design's Testing/Verification Strategy.
- Validation is performed locally without the live backend (`terraform init -backend=false`, plugin-only)
  because the real remote-state bucket has been deleted; this plan modifies no real state.
- SNS is OFF by default in DEV: zero SNS resources and empty `alarm_actions` until `enable_sns = true`.
- Non-duplication: the backend-owned ECS application log group (`${name_prefix}-app`) is REUSED, never
  recreated; the observability module declares no `aws_cloudwatch_log_group` and no autoscaling policy.
- Cost-optimized DEV: six standard alarms + one dashboard, SNS off, 7-day log retention; no NAT gateway,
  VPC endpoint, oversized compute, or ALB access-log S3 bucket is introduced by this module.
- AI-assisted CloudWatch troubleshooting (Query generator / results summarization) is documentation-only in
  the design. It layers on the same backend-owned log group and the same metrics, provisions NO Terraform
  resource (no Bedrock, Amazon Q, OpenSearch, or paid AI infrastructure), and therefore introduces NO tasks
  that create Terraform resources.
- The edge CloudFront VPC Origin architecture is NOT modified; observability is additive and observe-only.
- Applying to shared dev infrastructure is OUT OF SCOPE for this spec and gated on explicit operator
  confirmation; this plan does NOT auto-apply.

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "2.1"] },
    { "id": 1, "tasks": ["2.2"] },
    { "id": 2, "tasks": ["6.1"] },
    { "id": 3, "tasks": ["3.1", "4.1", "4.2", "5.1", "7.1"] },
    { "id": 4, "tasks": ["8"] },
    { "id": 5, "tasks": ["9.1"] },
    { "id": 6, "tasks": ["9.2", "9.3", "9.4"] },
    { "id": 7, "tasks": ["10.1"] },
    { "id": 8, "tasks": ["10.2"] },
    { "id": 9, "tasks": ["11.1"] },
    { "id": 10, "tasks": ["12"] }
  ]
}
```
