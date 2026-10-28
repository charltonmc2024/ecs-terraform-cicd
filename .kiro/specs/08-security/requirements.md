# Requirements Document

## Introduction

This spec covers a new reusable Terraform security module for the Erudition Solution development
environment. The `Security_Module` is a cross-cutting security module at
`ecs-terraform/modules/security/`, composed by the Terraform root module at `ecs-terraform/envs/dev/`.
Its deliverables form an EXPANDED, cost-optimized security baseline whose every billable control is
optional and defaults OFF: an optional AWS WAFv2 web ACL (scope `CLOUDFRONT`) that attaches to the single
existing CloudFront distribution owned by the edge module, an optional CloudTrail management-events trail,
optional Amazon EventBridge security-event rules, and an optional Amazon SNS security-alerts topic. Its
supporting deliverables are a security-architecture review, a controlled strategy for the remaining
optional detective services (GuardDuty, AWS Config, Security Hub, Amazon Inspector enhanced scanning, KMS),
a confirmation of the existing ECR image-scanning configuration, Terraform validation, cost analysis, and
documentation updates.

The platform is an adaptive educational assessment application for school districts, served from the
internet through CloudFront, which forwards `/api/*` and `/v1/*` to an internal Application Load Balancer
through a CloudFront VPC Origin, with the API running on ECS Fargate in private subnets and the database
hosted externally on MongoDB Atlas M0 reached over NAT egress. CloudFront is the only internet-facing
resource, so the optional WAFv2 web ACL at that edge is the platform's primary application-layer request
filter; every WAF rule in this spec exists to inspect inbound requests before they reach the private origin.

### Expanded cost-optimized architecture and security-event flow

The security architecture now spans four optional, independently toggled capabilities, each gated by a
boolean that defaults to `false` so the cost-optimized DEV baseline creates no billable security resource:

- **WAF (optional, `enable_waf`, default `false`)** — request filtering at the CloudFront edge. The
  cost-optimized baseline, when enabled, is the AWS Managed Common Rule Set in count mode plus exactly one
  configurable rate-based rule; additional managed groups are configurable but off by default.
- **CloudTrail (optional, `enable_cloudtrail`, default `false`)** — a single management-events-only trail,
  created only after confirming no suitable existing account or organization trail already provides
  management-event coverage that can be reused.
- **EventBridge security rules (optional, `enable_security_alerts`, default `false`)** — targeted rules on
  the default event bus that match security-relevant API activity recorded by CloudTrail.
- **SNS security-alerts topic (optional, `enable_security_alerts`, default `false`)** — the notification
  path for the EventBridge rules.

The security-event flow is: a security-relevant API call (for example an IAM policy change, a security
group ingress/egress modification, or a CloudTrail configuration change) is recorded by an active
CloudTrail trail and delivered to the default event bus, where a targeted EventBridge rule matches the
event and publishes it to the SNS security-alerts topic, which delivers an email to a subscribed operator
after that operator confirms the subscription. Because EventBridge rules that match CloudTrail-delivered
API activity require a suitable active trail with logging, the EventBridge capability depends on either a
reused existing trail or the optional new trail being enabled; without such a trail those rules do not
match.

### Scope constraint — implementation and validation only (no deployment)

This spec is an IMPLEMENTATION AND VALIDATION task only. It writes Terraform configuration, formats it,
validates it, and reviews a plan at most. It performs NO deployment: no `terraform apply`, no
`terraform destroy`, no live AWS resource creation, modification, or deletion, and no change to running
infrastructure. Every requirement below is satisfied by authored configuration, review output, or
validation output — not by a deployed resource. A successful `terraform validate` or `terraform plan` does
NOT authorize `terraform apply` within this spec.

### Verified current-state facts (established by inspecting the repository)

Several ownership and configuration facts cross module boundaries and are stated up front because they
constrain this spec:

- **The CloudFront distribution already exists and is owned by the edge module, with no web ACL attached.**
  The edge module declares `aws_cloudfront_distribution.this` (`modules/edge/cloudfront.tf`) and sets no
  `web_acl_id`. The edge module currently declares no WAF or web ACL variable, and its outputs are only
  `cloudfront_distribution_id`, `cloudfront_domain_name`, and `frontend_bucket_name`. When WAF is enabled,
  the WAFv2 web ACL from this spec MUST attach to THIS existing distribution. The `Security_Module` MUST
  NOT create a second CloudFront distribution and MUST NOT duplicate the edge module's distribution. The
  attachment is expressed by giving the edge module an OPTIONAL `web_acl_id` input (type `string`, default
  `null`) that the Dev_Root wires from the Security_Module output, which resolves the prior open design
  question. The integration MUST preserve the `network → backend → edge` dependency direction and introduce
  no circular module dependency.

- **The dev root declares only the default-region AWS provider; there is no `aws.us_east_1` alias.** The
  dev root `providers.tf` declares a single `provider "aws"` using `region = var.aws_region` with
  `default_tags`, and no `aws.us_east_1` alias yet. A WAFv2 web ACL with scope `CLOUDFRONT` MUST be created
  in `us-east-1`. This spec therefore requires declaring an `aws.us_east_1` provider alias in the dev root
  and passing it explicitly to the `Security_Module` through an explicit provider mapping
  (`providers = { aws = aws.us_east_1 }`). The `us-east-1` provider requirement remains even though WAF is
  now optional, because the WAF resources are created in `us-east-1` whenever `enable_waf` is `true`.

- **ECR basic scan-on-push is already enabled by the backend module.** The backend module declares
  `aws_ecr_repository.app` (`modules/backend/ecr.tf`) with
  `image_scanning_configuration { scan_on_push = true }`. The ECR requirement in this spec is therefore a
  REVIEW-AND-DOCUMENT requirement: confirm and retain the existing basic scanning, do NOT create a
  duplicate or conflicting ECR scanning configuration, and do NOT enable Amazon Inspector enhanced scanning
  automatically.

- **The observability module already implements a reusable SNS pattern that this spec MIRRORS.** The
  observability module (`modules/observability/sns.tf`) declares a count-gated `aws_sns_topic` named
  `"${name_prefix}-alarms"`, an `aws_sns_topic_policy` built from an IAM policy document with a service
  principal and an `aws:SourceAccount` condition using `data.aws_caller_identity.current`, and an optional
  `aws_sns_topic_subscription` (protocol `email`) created only when the feature is enabled AND a non-empty
  email is supplied. It documents that the AWS-managed alias `alias/aws/sns` cannot be used for encrypted
  publish from an AWS service and that server-side encryption at rest is intentionally omitted for DEV (TLS
  in transit only). The security-alerts SNS topic in this spec mirrors these conventions, with the service
  principal being EventBridge (`events.amazonaws.com`) rather than CloudWatch.

- **Existing backend security controls are already in place and MUST be preserved.** The backend module
  already defines separate ECS execution and ECS task IAM roles with ECS trust policies, scoped Secrets
  Manager read access, an internal ALB security group, an ECS task security group, ALB ingress via the
  CloudFront origin-facing managed prefix list, ALB egress to the ECS security group on the application
  port, ECS ingress only from the ALB, and private ECS tasks with no public IP. This spec MUST NOT
  duplicate or modify these controls unless the security review identifies a verified security defect.

- **Existing CloudWatch monitoring is already implemented by the observability module and MUST NOT be
  duplicated.** The already-implemented CloudWatch alarms, dashboard, and optional SNS alarm topic owned by
  the observability module are reused as-is; this spec adds a separate security-event notification path and
  does not re-create CloudWatch monitoring.

- **Application and data bootstrap values MUST be preserved.** This spec MUST NOT change the MongoDB Secrets
  Manager ARN references (`app_secret_arn`, `staff_admin_secret_arn`), the MongoDB database names
  (`teacher_student_db`, `admin_staff_mongodb`), the application image tag (`latest`), the ECS
  `desired_count` (0), the ECS autoscaling `min_capacity` (0), the NAT Gateway configuration, or any
  database credential.

This spec is DEV only. It MUST NOT create `envs/staging` or `envs/prod` and MUST NOT create staging or
production resources. The `Security_Module` stays environment-independent: typed variables with no DEV
literals inside the module, and DEV values supplied through `envs/dev/terraform.tfvars`. Every optional
billable security feature defaults to OFF, and WAF managed rule groups start in COUNT (override) mode so no
legitimate traffic is blocked before false-positive evaluation.

## Glossary

- **Security_Module**: The reusable Terraform module at `ecs-terraform/modules/security/` that owns the
  optional WAFv2 web ACL, the optional CloudTrail trail, the optional EventBridge security rules, the
  optional SNS security-alerts topic, and any other toggle-gated security-service resources for the
  development environment.
- **Dev_Root**: The Terraform root module and single source of truth for the development environment at
  `ecs-terraform/envs/dev/`, which composes the network, backend, edge, observability, and security modules
  and declares the provider configuration.
- **Edge_Module**: The existing module at `ecs-terraform/modules/edge/` that owns
  `aws_cloudfront_distribution.this`, the platform's only internet-facing resource.
- **Backend_Module**: The existing module at `ecs-terraform/modules/backend/` that owns ECR, the internal
  ALB, ECS Fargate resources, the ECS execution and task IAM roles, the security groups, and the Secrets
  Manager integration.
- **Observability_Module**: The existing module at `ecs-terraform/modules/observability/` that owns the
  CloudWatch alarms, the dashboard, and the optional alarm SNS topic whose conventions the security-alerts
  topic mirrors.
- **CloudFront_Distribution**: The existing `aws_cloudfront_distribution.this` owned by the Edge_Module,
  which currently has no `web_acl_id` set.
- **enable_waf**: The boolean input variable (default `false`) that gates every WAFv2 resource and the
  CloudFront web ACL association; while `false`, zero WAFv2 resources are created and the distribution has
  no web ACL association.
- **Web_ACL**: The optional `aws_wafv2_web_acl` created by the Security_Module with scope `CLOUDFRONT` in
  `us-east-1` only when `enable_waf` is `true`, attached to the CloudFront_Distribution.
- **Common_Rule_Set**: The AWS managed rule group `AWSManagedRulesCommonRuleSet`, the cost-optimized WAF
  baseline alongside the rate-based rule.
- **Known_Bad_Inputs_Rule_Set**: The AWS managed rule group `AWSManagedRulesKnownBadInputsRuleSet`, now an
  OPTIONAL/configurable managed group rather than a mandatory one.
- **Rate_Based_Rule**: The single WAFv2 rate-based rule with a configurable request-rate limit, part of the
  cost-optimized WAF baseline.
- **Count_Mode**: A managed-rule-group override that causes matched requests to be counted and labeled
  rather than blocked, used for initial deployment and false-positive evaluation.
- **Block_Mode**: The enforcement state in which a rule blocks matched requests, adopted only after
  false-positive evaluation and an explicit configuration change.
- **US_East_1_Provider**: The `aws.us_east_1` provider alias declared in the Dev_Root and passed explicitly
  to the Security_Module, required because WAFv2 `CLOUDFRONT` scope resources live in `us-east-1`.
- **ECR_Repository**: The existing `aws_ecr_repository.app` owned by the Backend_Module, already configured
  with `scan_on_push = true` (basic scanning).
- **Basic_Scanning**: ECR basic image scanning on push (already enabled), which performs CVE scanning using
  the Clair-based open-source feed at no additional per-scan charge.
- **Enhanced_Scanning**: Amazon Inspector enhanced ECR scanning, a separately enabled, account-level,
  billable capability that is NOT enabled by this spec.
- **enable_cloudtrail**: The boolean input variable (default `false`) that gates the Optional_Trail and its
  backing S3 bucket.
- **Optional_Trail**: An optional `aws_cloudtrail` management-events-only trail plus its backing S3 bucket,
  gated by `enable_cloudtrail` and created only when no suitable existing trail is reused.
- **enable_security_alerts**: The boolean input variable (default `false`) that gates every EventBridge
  security rule and the SNS security-alerts topic; while `false`, zero EventBridge or SNS security
  resources are created.
- **EventBridge_Security_Rules**: The targeted `aws_cloudwatch_event_rule` resources on the default event
  bus that match security-relevant API activity (IAM policy changes, security group ingress/egress
  modifications, and CloudTrail configuration changes) and target the Security_Alerts_Topic.
- **Security_Alerts_Topic**: The single `aws_sns_topic` created when `enable_security_alerts` is `true`,
  named from the Name_Prefix, that receives EventBridge security events and delivers email notifications.
- **Optional_Security_Service**: Any of GuardDuty, AWS Config, Security Hub, Amazon Inspector enhanced
  scanning, or a customer-managed KMS key (CMK) evaluated by this spec, each disabled by default and
  deferred for DEV.
- **Security_Review_Findings**: The written output of the security-architecture review that separates
  verified security defects from optional improvements.
- **Name_Prefix**: The derived naming prefix `"${app_name}-${environment}"` used to name security resources
  consistently.
- **Common_Tags**: The tag set with keys `Project`, `Environment`, `ManagedBy`, and `Owner` passed from the
  Dev_Root into the Security_Module.

## Requirements

### Requirement 1: Reusable, environment-independent security module

**User Story:** As an infrastructure engineer, I want a reusable security module driven entirely by typed inputs, so that the development environment gains edge protection today and future environments can consume the same module without redesign.

#### Acceptance Criteria

1. THE Security_Module SHALL be located at the path `ecs-terraform/modules/security/` and SHALL organize its configuration across the files `main.tf`, `waf.tf`, `cloudtrail.tf`, `eventbridge.tf`, `sns.tf`, `variables.tf`, `outputs.tf`, and `versions.tf`.
2. WHERE a distinct resource grouping is introduced that does not belong to any of the required files, THE Security_Module SHALL place that grouping in an additional `.tf` file and SHALL NOT create any `.tf` file containing zero resource, data, variable, output, or local declarations.
3. THE Security_Module SHALL derive every security resource name from a `Name_Prefix` local whose value equals the concatenation of the `app_name` input, a single hyphen, and the `environment` input, and SHALL NOT restate the `"${app_name}-${environment}"` naming expression in more than one location in the module source.
4. THE Security_Module SHALL declare every environment-specific value as an input variable that has an explicit `type` declaration and a `description` of 1 to 1024 characters, and SHALL NOT embed a development-specific literal value in the module source.
5. THE Security_Module SHALL declare an inline `terraform` block specifying `required_version = "~> 1.16.0"` and a `required_providers` entry for `aws` with `source = "hashicorp/aws"` and `version = ">= 6.67.0, < 7.0.0"`, and SHALL NOT declare a `backend` block.
6. WHERE a resource supports tagging, THE Security_Module SHALL apply the `Common_Tags` set containing exactly the four keys `Project`, `Environment`, `ManagedBy`, and `Owner` passed from the Dev_Root, merged with a single resource-specific `Name` tag.
7. THE Security_Module SHALL obtain every AWS account identifier, ARN, CloudFront distribution id, and managed-policy id from an input variable, a module output, a data source, or a Terraform resource reference, and SHALL NOT contain any such value as a hardcoded literal in the module source.
8. IF an input variable is declared without an explicit `type` declaration, THEN THE Security_Module SHALL fail `terraform validate` and SHALL return an error message indicating the variable missing its type, while preserving the module source unchanged.

### Requirement 2: us-east-1 provider for CloudFront-scoped WAF

**User Story:** As an infrastructure engineer, I want the dev root to provide a us-east-1 provider to the security module, so that the optional CloudFront-scoped WAFv2 web ACL is created in the only region AWS permits.

#### Acceptance Criteria

1. THE Dev_Root SHALL declare a `US_East_1_Provider` provider alias `aws.us_east_1` with `region = "us-east-1"` in `envs/dev/providers.tf`.
2. THE Dev_Root SHALL pass the `US_East_1_Provider` to the Security_Module through an explicit provider mapping `providers = { aws = aws.us_east_1 }` on the `module "security"` block.
3. WHERE `enable_waf` is `true`, WHEN the Security_Module creates the `Web_ACL`, THE Security_Module SHALL set its scope to `CLOUDFRONT` using the AWS provider it receives.
4. IF the AWS provider received by the Security_Module resolves to a region other than `us-east-1` while `enable_waf` is `true`, THEN THE Security_Module SHALL fail at plan or apply with an error indicating that a `CLOUDFRONT`-scoped Web_ACL requires `us-east-1`, and SHALL NOT create the `Web_ACL`.
5. THE Security_Module SHALL NOT declare its own `provider` block and SHALL rely solely on the explicitly mapped provider from the Dev_Root.
6. THE `US_East_1_Provider` declaration SHALL carry the identical `default_tags` common tag set (same tag keys and values) used by the default-region provider so that every resource created through it is tagged consistently with resources created through the default-region provider.
7. THE `US_East_1_Provider` requirement SHALL remain in place even while `enable_waf` is `false`, so that enabling WAF later requires no additional provider wiring.

### Requirement 3: Optional AWS WAFv2 web ACL gated by enable_waf

**User Story:** As a security engineer, I want an optional WAFv2 web ACL whose cost-optimized baseline is the Common Rule Set in count mode plus one rate-based rule, so that edge request filtering is available when enabled without incurring recurring WAF cost by default.

#### Acceptance Criteria

1. THE Security_Module SHALL expose an `enable_waf` boolean input variable that defaults to `false`.
2. WHILE `enable_waf` is `false`, THE Security_Module SHALL create zero WAFv2 resources and the CloudFront_Distribution SHALL have no web ACL association.
3. WHERE `enable_waf` is `true`, THE Security_Module SHALL create exactly one `Web_ACL` (`aws_wafv2_web_acl`) with scope equal to `CLOUDFRONT` created through the `US_East_1_Provider`.
4. WHERE `enable_waf` is `true`, THE Security_Module SHALL set the `Web_ACL` default action from a typed string input variable whose allowed values are exactly `allow` and `block` and whose default value is `allow`.
5. IF the `Web_ACL` default action input variable is any value other than `allow` or `block`, THEN THE Security_Module SHALL reject the configuration with a validation error indicating the allowed values.
6. WHERE `enable_waf` is `true`, THE Security_Module SHALL include the `Common_Rule_Set` (`AWSManagedRulesCommonRuleSet`) managed rule group as a rule in the `Web_ACL` with its rule action set to `none` so the managed group's own actions apply, forming the cost-optimized baseline together with the `Rate_Based_Rule`.
7. WHERE `enable_waf` is `true`, THE Security_Module SHALL include exactly one `Rate_Based_Rule` whose request-rate limit is set from a typed integer input variable, whose aggregation is per source IP over the WAFv2 fixed 5-minute (300-second) evaluation window.
8. WHERE `enable_waf` is `true`, THE Security_Module SHALL include the `Known_Bad_Inputs_Rule_Set` (`AWSManagedRulesKnownBadInputsRuleSet`) and any additional AWS managed rule group ONLY when a dedicated configurable input enables that group, each such group defaulting to disabled so the baseline remains the Common_Rule_Set plus the Rate_Based_Rule.
9. THE Security_Module SHALL NOT include any premium or paid managed rule group, AWS WAF Bot Control, CAPTCHA actions, or Challenge actions in the `Web_ACL`.
10. THE Security_Module SHALL NOT declare any `aws_wafv2_web_acl_logging_configuration` resource.
11. WHERE `enable_waf` is `true`, THE Security_Module SHALL constrain the `Rate_Based_Rule` request-rate limit input variable to an integer between 100 and 2,000,000,000 inclusive and SHALL default it to 2000 requests per 5-minute window for DEV.
12. IF the `Rate_Based_Rule` request-rate limit input variable is outside the range 100 to 2,000,000,000 inclusive, THEN THE Security_Module SHALL reject the configuration with a validation error indicating the allowed range.
13. WHERE `enable_waf` is `true`, THE Security_Module SHALL assign each rule in the `Web_ACL` a distinct integer `priority` such that no two rules share the same `priority` value and priorities increase in ascending order across the rules.
14. WHERE `enable_waf` is `true`, THE Security_Module SHALL enable CloudWatch metrics and a distinct metric name for the `Web_ACL` and for each rule within it, and SHALL derive the `Web_ACL` name, each rule name, and each metric name from the `Name_Prefix` input without any hardcoded name string.
15. THE Security_Module SHALL expose the WAFv2 configuration so that it can be adjusted for future production hardening (for example enabling additional managed groups and moving rules to `Block_Mode`) without editing module source.

### Requirement 4: Managed rule groups start in count mode

**User Story:** As a security engineer, I want managed rule groups to start in count mode, so that legitimate assessment traffic is never blocked before false positives have been evaluated.

#### Acceptance Criteria

1. WHERE `enable_waf` is `true`, THE Security_Module SHALL apply a managed-rule-group override that places the `Common_Rule_Set`, and any additional enabled managed rule group, in `Count_Mode` by default.
2. WHERE `enable_waf` is `true`, THE Security_Module SHALL expose the enforcement mode of each managed rule group as a typed input variable that accepts only the values `Count_Mode` or `Block_Mode`, defaults to `Count_Mode`, and rejects any other value with a validation error indicating the allowed values.
3. WHILE a managed rule group is in `Count_Mode`, THE Security_Module SHALL cause every matched request to be counted and labeled, and SHALL NOT block any matched request.
4. WHEN the enforcement-mode input for a managed rule group is set to `Block_Mode`, THE Security_Module SHALL cause matched requests for that rule group to be blocked without requiring any change to module source.
5. WHERE `enable_waf` is `true`, THE Rate_Based_Rule SHALL use a configurable action input that accepts only the values `Count_Mode` or `Block_Mode`, defaults to `Count_Mode`, and allows the rate-based rule to be moved from `Count_Mode` to `Block_Mode` without editing module source.
6. THE requirements documentation SHALL record each rule intended to transition from `Count_Mode` to `Block_Mode` and SHALL describe how to evaluate false positives using the counted and labeled requests before that transition.

### Requirement 5: CloudWatch visibility for every WAF rule and the web ACL

**User Story:** As an operator, I want CloudWatch metrics and sampled requests for the web ACL and every rule when WAF is enabled, so that I can evaluate rule effectiveness and false positives before enabling blocking.

#### Acceptance Criteria

1. WHERE `enable_waf` is `true`, THE Security_Module SHALL set the `Web_ACL` default visibility configuration with CloudWatch metrics enabled and sampled-request collection enabled.
2. WHERE `enable_waf` is `true`, THE Security_Module SHALL set the visibility configuration of every rule within the `Web_ACL`, including the `Common_Rule_Set`, the `Rate_Based_Rule`, and any additional enabled managed rule group, with CloudWatch metrics enabled and sampled-request collection enabled.
3. WHERE `enable_waf` is `true`, THE Security_Module SHALL derive each visibility metric name from the `Name_Prefix` input such that each metric name begins with the `Name_Prefix` value and contains no hardcoded account-specific or environment-specific literal.
4. WHERE `enable_waf` is `true`, THE Security_Module SHALL assign each rule a visibility metric name that is unique across all rules in the `Web_ACL` such that no two rules publish to the same metric name.
5. WHERE `enable_waf` is `true`, THE Security_Module SHALL constrain each visibility metric name to a maximum of 128 characters composed only of alphanumeric, hyphen, and underscore characters.
6. IF a visibility metric name cannot be derived from the `Name_Prefix` input because the input is empty or null while `enable_waf` is `true`, THEN THE Security_Module SHALL fail validation and return an error indicating that `Name_Prefix` is required, without creating the `Web_ACL`.

### Requirement 6: Attach the web ACL to the existing CloudFront distribution via an optional edge input

**User Story:** As an infrastructure engineer, I want the optional web ACL attached to the single existing CloudFront distribution through an optional edge input, so that edge protection applies to live traffic when enabled without creating a duplicate distribution and without breaking the distribution when WAF is disabled.

#### Acceptance Criteria

1. WHERE `enable_waf` is `true`, THE Security_Module SHALL expose the `Web_ACL` ARN as an output named `web_acl_arn`, whose value is a non-empty string beginning with `arn:`.
2. WHILE `enable_waf` is `false`, THE Security_Module `web_acl_arn` output SHALL be `null`.
3. THE Security_Module SHALL NOT create, replace, or duplicate any `aws_cloudfront_distribution` resource, and the total count of `aws_cloudfront_distribution` resources in the configuration SHALL remain exactly one.
4. THE Edge_Module SHALL accept a `web_acl_id` input variable of type `string` that defaults to `null`.
5. WHILE the Edge_Module `web_acl_id` input is `null`, including whenever `enable_waf` is `false`, THE Edge_Module SHALL create the CloudFront_Distribution with no web ACL association such that the distribution remains valid and deployable.
6. WHEN the Dev_Root supplies a non-null `web_acl_id` sourced from the Security_Module `web_acl_arn` output, THE Edge_Module SHALL set the distribution `web_acl_id` to that ARN and SHALL NOT hardcode the ARN.
7. THE Dev_Root SHALL wire the Security_Module `web_acl_arn` output to the Edge_Module `web_acl_id` input through module-output references only, preserving the `network → backend → edge` dependency direction and introducing no circular module dependency between the Edge_Module and the Security_Module.

### Requirement 7: Retain existing ECR basic scanning without duplication

**User Story:** As a security engineer, I want the existing ECR basic image scanning retained and documented, so that image vulnerabilities continue to surface on push without duplicate or conflicting configuration and without silently enabling billable enhanced scanning.

#### Acceptance Criteria

1. THE Security_Module SHALL NOT declare any `aws_ecr_repository` resource and SHALL NOT declare any `image_scanning_configuration` that duplicates or conflicts with the existing `ECR_Repository` configuration owned by the Backend_Module.
2. THE spec SHALL confirm that the existing `ECR_Repository` owned by the Backend_Module retains `scan_on_push = true` (Basic_Scanning) and SHALL leave that configuration unchanged, declaring exactly one `image_scanning_configuration` for the `ECR_Repository` across all modules.
3. THE Security_Module SHALL NOT declare any resource or configuration that enables Amazon Inspector Enhanced_Scanning, and SHALL leave the account-level Amazon Inspector Enhanced_Scanning setting unmodified.
4. THE documentation SHALL state that Basic_Scanning is the repository-level `scan_on_push` capability that runs on image push, and SHALL state that Enhanced_Scanning is an account-level, billable Amazon Inspector capability, including at least one observable distinction (scope: repository-level versus account-level, and cost: no additional charge versus billable).
5. THE documentation SHALL describe a Jenkins pipeline stage that gates a deployment on ECR scan findings, including querying scan results for a pushed image, comparing finding severity against a configurable severity threshold, and failing the stage when one or more findings are at or above that threshold.
6. IF the Basic_Scanning scan results for a pushed image are not available within 300 seconds of the push, THEN the documented Jenkins pipeline stage SHALL fail the stage and surface an indication that scan results were unavailable, without deploying the image.

### Requirement 8: CloudTrail reuse-first, optional default-off management trail

**User Story:** As a security engineer, I want existing CloudTrail coverage reused where suitable and a new trail only when needed and explicitly enabled, so that management-event auditing is available without duplicate trails or unnecessary recurring cost.

#### Acceptance Criteria

1. WHEN the spec is implemented, THE spec SHALL first determine whether a suitable existing account trail or organization trail already provides management-event coverage for the target AWS account and region, and WHERE such a suitable trail exists, THE spec SHALL reuse it rather than creating a new trail.
2. THE spec SHALL NOT create a trail whose name or configuration duplicates an existing account or organization trail.
3. THE documentation SHALL state that AWS provides CloudTrail Event History covering the most recent 90 days of management events without a configured trail, and SHALL state its limitations relative to a configured trail, specifically that it retains only 90 days, covers management events only (not data events), and does not deliver logs to a durable S3 bucket.
4. THE Security_Module SHALL expose an `enable_cloudtrail` boolean input variable that defaults to `false`.
5. WHILE `enable_cloudtrail` is `false`, THE Security_Module SHALL create zero `aws_cloudtrail` resources, zero trail S3 bucket resources, and zero other trail-related resources.
6. WHERE `enable_cloudtrail` is `true` and no suitable existing trail is reused, THE Security_Module SHALL create exactly one `Optional_Trail` that records management events only, backed by exactly one S3 bucket that has block-public-access enabled on all four settings, server-side encryption enabled, and log file validation enabled.
7. WHERE `enable_cloudtrail` is `true` and the `Optional_Trail` is created, THE Security_Module SHALL apply an S3 lifecycle rule to the trail bucket that expires trail objects after a bounded retention period of no more than 365 days, such that no trail object is retained indefinitely.
8. THE `Optional_Trail` SHALL NOT enable data events, CloudTrail Lake, or any other separately billed CloudTrail feature, and SHALL NOT deliver trail logs to CloudWatch Logs, unless such a feature is explicitly requested and approved.
9. THE EventBridge_Security_Rules that match CloudTrail-delivered API activity SHALL require a suitable active trail with logging — either a reused existing trail or the `Optional_Trail` enabled — and WHILE no such active trail exists, those rules SHALL NOT match any event.

### Requirement 9: Amazon EventBridge security-event rules

**User Story:** As a security engineer, I want targeted EventBridge rules that detect security-relevant API activity, so that IAM, security-group, and CloudTrail configuration changes trigger a notification without standing up custom event-processing services.

#### Acceptance Criteria

1. THE Security_Module SHALL expose an `enable_security_alerts` boolean input variable that defaults to `false`.
2. WHILE `enable_security_alerts` is `false`, THE Security_Module SHALL create zero EventBridge resources and zero SNS security-alert resources.
3. WHERE `enable_security_alerts` is `true`, THE Security_Module SHALL create `EventBridge_Security_Rules` on the DEFAULT event bus that match at least IAM policy changes, security group ingress and egress modifications (authorize and revoke ingress and egress), and CloudTrail configuration changes (`StopLogging`, `UpdateTrail`, and `DeleteTrail`).
4. WHERE `enable_security_alerts` is `true`, THE Security_Module SHALL define each EventBridge event pattern narrowly by specific `eventSource` and `eventName` values, and SHALL NOT use a broad catch-all pattern that matches all API activity.
5. WHERE `enable_security_alerts` is `true`, THE Security_Module SHALL set each `EventBridge_Security_Rule` target to the `Security_Alerts_Topic`.
6. THE EventBridge_Security_Rules SHALL depend on a suitable active CloudTrail trail with logging (a reused existing trail or the enabled `Optional_Trail`), and THE documentation SHALL state this dependency explicitly.
7. THE Security_Module SHALL NOT create any AWS Lambda function or other custom event-processing service to implement the EventBridge_Security_Rules.

### Requirement 10: Amazon SNS security-alerts topic

**User Story:** As a security engineer, I want a single SNS security-alerts topic mirroring the observability SNS conventions, so that EventBridge security events reach an operator by email without hardcoded account identifiers or custom processors.

#### Acceptance Criteria

1. WHERE `enable_security_alerts` is `true`, THE Security_Module SHALL create exactly one `Security_Alerts_Topic` (`aws_sns_topic`) whose name is derived from the `Name_Prefix` input with no hardcoded name string.
2. THE Security_Module SHALL expose a dedicated security-alerts email input variable of type `string` that defaults to the empty string `""`.
3. WHERE `enable_security_alerts` is `true` AND the security-alerts email input is a non-empty string, THE Security_Module SHALL create exactly one `aws_sns_topic_subscription` with protocol `email` and the supplied endpoint.
4. WHILE `enable_security_alerts` is `true` AND the security-alerts email input is the empty string, THE Security_Module SHALL create the `Security_Alerts_Topic` with no subscription.
5. WHERE `enable_security_alerts` is `true`, THE Security_Module SHALL attach a topic policy allowing the EventBridge service principal `events.amazonaws.com` to publish to the `Security_Alerts_Topic`, scoped by an `aws:SourceAccount` condition whose value is obtained from `data.aws_caller_identity.current` with no hardcoded account id.
6. THE Security_Module SHALL NOT create any AWS Lambda function or other custom processor to handle messages published to the `Security_Alerts_Topic`.
7. THE Security_Module SHALL follow the DEV server-side-encryption-at-rest decision consistent with the Observability_Module alarm topic, creating the `Security_Alerts_Topic` without server-side encryption at rest (TLS in transit only), and THE documentation SHALL record this at-rest choice and note that the service principal for this topic is EventBridge rather than CloudWatch.
8. THE documentation SHALL explain that an email subscription remains in a pending state until the recipient confirms the subscription, and SHALL describe the required subscription-confirmation step.

### Requirement 11: Controlled review of remaining optional security services

**User Story:** As a security engineer, I want each remaining optional security service evaluated rather than enabled automatically, so that DEV adopts only justified, cost-conscious controls and defers the rest.

#### Acceptance Criteria

1. THE Security_Review_Findings SHALL evaluate each of GuardDuty, AWS Config, Security Hub, Amazon Inspector Enhanced_Scanning, and customer-managed KMS keys, stating for each the security risk addressed, whether it is already implemented (true or false), whether it is recommended for DEV (true or false), its estimated monthly recurring cost in USD, and whether it should be deferred for DEV (true or false).
2. IF the Security_Review_Findings omits any of the five required attributes (security risk addressed, already-implemented flag, recommended-for-DEV flag, estimated monthly cost in USD, deferred flag) for any one of the evaluated services, THEN THE Security_Review_Findings SHALL be treated as incomplete and SHALL present an indication identifying each service and attribute that is missing.
3. THE Security_Module SHALL NOT enable any account-wide Optional_Security_Service (GuardDuty, AWS Config, Security Hub, or Amazon Inspector) when every such service's toggle input variable is `false`.
4. WHERE any one of the account-wide Optional_Security_Service controls (GuardDuty, AWS Config, Security Hub, Amazon Inspector) is prepared in configuration, THE Security_Module SHALL gate that service behind a dedicated boolean toggle input variable that defaults to `false`.
5. WHILE every Optional_Security_Service toggle input variable retains its default value of `false`, THE Security_Module SHALL create zero account-wide Optional_Security_Service resources.
6. THE Security_Module SHALL NOT create a customer-managed KMS key (CMK) while no input variable explicitly requires a customer-managed KMS key, relying on AWS-managed encryption for DEV.
7. THE Security_Review_Findings SHALL state, for each account-wide detective service (GuardDuty, AWS Config, Security Hub, Amazon Inspector), a recommendation to keep it deferred for DEV unless a specific stated requirement justifying that service is recorded in the Security_Review_Findings.

### Requirement 12: Security-architecture review producing findings, not changes

**User Story:** As a security reviewer, I want a written review of the existing architecture, so that verified defects are separated from optional improvements before any change is made.

#### Acceptance Criteria

1. WHEN a security-architecture review is performed, THE Security_Review_Findings SHALL produce a written finding for each of the following review areas: IAM least privilege, Secrets Manager permissions, security-group ingress and egress, the CloudFront-to-ALB restriction, ECS private networking, MongoDB Atlas connectivity, S3 public-access blocking, CloudFront OAC, encryption at rest, encryption in transit, CloudWatch log retention, ECR image scanning, sensitive Terraform outputs, and Terraform state handling.
2. THE Security_Review_Findings SHALL assign to every recorded finding exactly one classification label from the set {VERIFIED_DEFECT, OPTIONAL_IMPROVEMENT}.
3. IF a finding is classified as VERIFIED_DEFECT, THEN THE Security_Review_Findings SHALL record, for that finding, the review area, the observed condition, and the justification establishing it as a defect.
4. IF the Security_Review_Findings record no finding classified as VERIFIED_DEFECT that justifies a given change, THEN THE Security_Module SHALL NOT modify any existing Backend_Module IAM role, security group, Secrets Manager reference, or ECS networking setting.
5. THE Security_Review_Findings SHALL record a confirmation result of either CONFIRMED or NOT_CONFIRMED for each of the following conditions: ECS tasks are private with no public IP assigned, the ALB is internal, the frontend S3 bucket is private behind OAC, and no public exposure is introduced.
6. THE Security_Review_Findings SHALL record a confirmation result of either UNCHANGED or CHANGED for each of the following items: the MongoDB Secrets Manager ARN references, the MongoDB database names, the application image tag, the ECS `desired_count`, the ECS autoscaling `min_capacity`, and the NAT Gateway configuration.

### Requirement 13: Terraform validation without deployment

**User Story:** As an infrastructure engineer, I want the security changes formatted, validated, and planned without applying, so that correctness is confirmed while no live AWS resource is changed.

#### Acceptance Criteria

1. WHEN the validation workflow begins, THE spec SHALL run `terraform fmt -recursive` from `ecs-terraform/envs/dev` and SHALL confirm that a subsequent `terraform fmt -check -recursive` exits with status code 0 and reports zero files requiring formatting.
2. WHEN `terraform validate` is run from `ecs-terraform/envs/dev`, THE spec SHALL confirm the command exits with status code 0 reporting zero errors before marking validation complete.
3. IF `terraform validate` reports one or more errors, THEN THE spec SHALL resolve every reported error and re-run `terraform validate` until it exits with status code 0, and SHALL NOT proceed to planning while any validation error remains.
4. WHERE `enable_waf` is `true`, BEFORE relying on the WAF resources, THE spec SHALL confirm the resolved AWS provider version satisfies the declared constraint `>= 6.67.0, < 7.0.0` and supports WAFv2 `CLOUDFRONT` scope, and IF the resolved provider version falls outside this range or lacks WAFv2 `CLOUDFRONT` scope support, THEN THE spec SHALL halt and report the incompatibility before planning.
5. THE spec SHALL review all module references and outputs and SHALL confirm that zero resources duplicate an existing network, backend, edge, or observability resource, and IF any duplicate or conflicting resource is found, THEN THE spec SHALL report the specific duplicated resource and halt before planning.
6. THE spec SHALL review the git diff of all tracked files and SHALL confirm that zero secret values (AWS access keys, secret keys, connection URIs, tokens, passwords, or private keys) are introduced into any tracked file, and IF any secret value is detected, THEN THE spec SHALL report the file containing it and halt before completion.
7. THE spec SHALL NOT run `terraform apply` or `terraform destroy`, and SHALL NOT overwrite any existing saved `tfplan-dev` plan file, unless explicitly instructed by the user for that specific action.
8. BEFORE running any `terraform init` that downloads providers, THE spec SHALL state that the initialization downloads providers, so that the network-dependent action is understood prior to execution.

### Requirement 14: Cost controls and default-off billable features

**User Story:** As an engineer accountable for cost, I want recurring charges identified and every optional billable feature off by default, so that DEV spend stays predictable and no billable resource is enabled without an explicit decision.

#### Acceptance Criteria

1. THE documentation SHALL provide an estimated MONTHLY cost under low DEV traffic for each of the following and SHALL state at least one cost dimension for each: the WAFv2 web ACL (cost per web ACL, per rule, and per million requests), CloudTrail S3 storage, Amazon EventBridge, and Amazon SNS.
2. THE documentation SHALL identify, for the WAFv2 web ACL, CloudTrail S3 storage, EventBridge, and SNS, which costs vary with request volume, which vary with logging or storage volume, and which vary with notification volume.
3. THE Security_Module SHALL define each of the following optional billable features with a boolean enable variable whose default value is `false`: WAF (`enable_waf`), CloudTrail (`enable_cloudtrail`), security alerts covering EventBridge and SNS (`enable_security_alerts`), GuardDuty, Config, Security Hub, Inspector enhanced scanning, and any CMK.
4. WHERE an optional billable feature enable variable retains its default value of `false`, THE Security_Module SHALL create no billable resource for that feature.
5. THE documentation SHALL state that this spec prepares Terraform configuration only and does not deploy any billable resource, and SHALL distinguish the act of preparing configuration from the act of deploying a billable resource.
6. WHERE `enable_waf` is `true`, THE Rate_Based_Rule limit SHALL default to a stated requests-per-5-minute threshold, and each managed-rule-group enforcement mode SHALL default to count (non-blocking) rather than block.
7. THE Security_Module SHALL reuse the already-implemented controls — IAM least privilege, security groups, Secrets Manager, ECR Basic_Scanning, S3 encryption and public-access blocking, and the existing CloudWatch monitoring — and SHALL NOT duplicate any of them.
8. THE Security_Module SHALL NOT create a customer-managed KMS key unless an input variable explicitly requires one.
9. IF a recurring-cost resource is introduced into the Security_Module without a stated security, operational, or product purpose, THEN THE configuration SHALL be rejected during review as out of scope.

### Requirement 15: Documentation of the security module and strategy

**User Story:** As a team member, I want the project documentation updated to explain the expanded security design, so that the WAF rules, CloudTrail strategy, EventBridge and SNS security-event flow, ECR scanning, optional services, costs, validation, and future hardening are understood.

#### Acceptance Criteria

1. THE documentation SHALL explain the Security_Module architecture, state its position in the `network → backend → edge` dependency direction, identify the module that owns the CloudFront web ACL, and describe how the optional web ACL is attached to the CloudFront distribution through the Edge_Module `web_acl_id` input.
2. THE documentation SHALL describe the security-event flow from a security-relevant API call through CloudTrail delivery, an EventBridge rule match on the default event bus, publication to the Security_Alerts_Topic, and email delivery to a confirmed subscriber.
3. THE documentation SHALL state the CloudTrail dependency for the EventBridge_Security_Rules, explaining that those rules require a suitable active trail (a reused existing trail or the enabled `Optional_Trail`) and do not match events without it.
4. THE documentation SHALL describe the SNS email subscription-confirmation step and state that notifications are not delivered until the subscription is confirmed.
5. THE documentation SHALL describe the `enable_waf`, `enable_cloudtrail`, and `enable_security_alerts` toggles and state that each defaults to `false` so the cost-optimized DEV baseline creates no billable security resource.
6. THE documentation SHALL list each WAF rule by name, state whether each rule starts in `Count_Mode` or `Block_Mode`, identify which rules are intended to transition from `Count_Mode` to `Block_Mode`, and state the measurable condition — expressed as the maximum count of false-positive matches observed over a defined observation window — that must be met before a rule transitions.
7. THE documentation SHALL describe the ECR scanning posture by stating that Basic_Scanning is retained and Enhanced_Scanning is deferred, and SHALL describe the Jenkins scan-finding gate including the finding severity level at which the pipeline stage fails.
8. THE documentation SHALL state the estimated monthly cost in USD for the security module, list the cost controls applied, list the security validation procedures used to confirm the controls, and list the future production-hardening steps, including enabling WAF blocking and enabling the deferred detective services.
9. IF the documentation update modifies content outside the security topic, THEN THE documentation update SHALL be rejected and the non-security content SHALL be retained unchanged.

### Requirement 16: Repository scope and change discipline

**User Story:** As a maintainer, I want the work confined to this repository and limited to the smallest necessary change, so that sibling repositories, git state, and unrelated modules are untouched.

#### Acceptance Criteria

1. THE spec SHALL make file changes only within the `~/ecs-terraform-cicd` repository directory tree.
2. IF a proposed change targets a path outside the `~/ecs-terraform-cicd` repository directory tree, THEN THE spec SHALL reject the change and SHALL leave all files outside that tree unmodified.
3. THE spec SHALL keep the active git branch unchanged and SHALL NOT execute any commit, push, merge, rebase, or reset operation.
4. THE spec SHALL limit each change to only the files, modules, and resources required to satisfy the approved requirements, and SHALL leave all modules, resources, and architecture not named in the approved requirements unmodified.
5. THE spec SHALL preserve the MongoDB Secrets Manager ARN references (`app_secret_arn`, `staff_admin_secret_arn`), the MongoDB database names (`teacher_student_db`, `admin_staff_mongodb`), the application image tag (`latest`), the ECS `desired_count` (0), the ECS autoscaling `min_capacity` (0), the NAT Gateway configuration, and the existing network, backend, edge, and observability architecture unchanged.
6. THE spec SHALL NOT create the `envs/staging` directory, the `envs/prod` directory, or any resource designated for a staging or production environment.
7. IF a proposed change adds an AWS service or infrastructure resource that has no security, operational, or product purpose stated in the approved DEV requirements, THEN THE spec SHALL reject that addition.
