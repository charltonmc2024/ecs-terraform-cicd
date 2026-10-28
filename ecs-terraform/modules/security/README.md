# Security Module (`08-security`)

Cost-optimized, cross-cutting AWS security layer for the EruditionTX **development**
environment. Every billable capability it owns is **optional and disabled by default**, so
the DEV baseline adds **zero** security resources until an operator explicitly enables one.

> Scope: DEV only. This document describes the security topic. It does not change the
> Network, Backend, Edge, or Observability documentation.

---

## 1. Architecture and module integration

The module lives at `ecs-terraform/modules/security/` and is composed by the DEV root at
`ecs-terraform/envs/dev/`. It sits beside the Observability module as a cross-cutting layer
and does **not** alter the established `network → backend → edge` dependency direction.

```
                 (dev root wires outputs; no module-to-module cycle)
  network ──▶ backend ──▶ edge ◀── web_acl_id ◀── security (this module)
                                           observability (cross-cutting)
```

Ownership and integration points:

- **CloudFront web ACL ownership.** The **Edge** module owns the single CloudFront
  distribution (`aws_cloudfront_distribution.this`). The Security module owns the optional
  WAFv2 web ACL and *exposes its ARN* as the `web_acl_arn` output. The DEV root wires that
  output into the Edge module's optional `web_acl_id` input
  (`module.edge.web_acl_id = module.security.web_acl_arn`). When WAF is disabled the output
  is `null`, so the distribution is created with **no** web ACL association and remains
  valid. The Security module holds no reference to Edge and Edge holds none to Security, so
  there is **no circular dependency**.
- **Provider.** A `CLOUDFRONT`-scoped WAFv2 web ACL must be created in `us-east-1`. The DEV
  root declares an `aws.us_east_1` provider alias and maps it explicitly to this module
  (`providers = { aws = aws.us_east_1 }`). The module declares no provider of its own.
- **Backend / Observability.** The module does **not** duplicate or modify any Backend IAM
  role, security group, Secrets Manager reference, or ECS setting, and does not re-create the
  Observability CloudWatch monitoring. ECR scanning stays owned by the Backend module (see §5).

Module files: `main.tf` (provider requirements, `name_prefix` local, caller-identity data
source), `waf.tf`, `cloudtrail.tf`, `eventbridge.tf`, `sns.tf`, `variables.tf`, `outputs.tf`.

---

## 2. Default posture (current state)

All optional capabilities are **OFF by default**. With the DEV `terraform.tfvars` values, the
plan contains **zero** Security module resources.

| Toggle | Default | Controls |
| --- | --- | --- |
| `enable_waf` | `false` | WAFv2 web ACL + CloudFront association |
| `enable_cloudtrail` | `false` | Management-events CloudTrail trail + S3 bucket |
| `reuse_existing_trail` | `false` | Reuse a suitable existing trail instead of creating one |
| `enable_security_alerts` | `false` | EventBridge security rules + SNS alerts topic |
| `enable_known_bad_inputs` | `false` | Optional extra WAF managed group |
| `enable_guardduty` / `enable_config` / `enable_security_hub` / `enable_inspector_enhanced` | `false` | Deferred detective services (not implemented as resources; gating surface only) |

This reflects the implemented Terraform: each resource is `count`-gated on its toggle, and
every module output uses `one(...)` so it resolves to `null` when its feature is disabled.

---

## 3. AWS WAF

When `enable_waf = true`, the module creates exactly one `aws_wafv2_web_acl` (scope
`CLOUDFRONT`, in `us-east-1`) with `default_action = allow` by default. Rules, in priority
order:

| Priority | Rule | Type | Initial mode |
| --- | --- | --- | --- |
| 1 | `…-common-rule-set` (`AWSManagedRulesCommonRuleSet`) | AWS managed group | **COUNT** |
| 2 | `…-rate-limit` (rate-based, per source IP, 2000 req / 5 min default) | rate-based | **COUNT** |
| 3 | `…-known-bad-inputs` (`AWSManagedRulesKnownBadInputsRuleSet`) | AWS managed group, **only if** `enable_known_bad_inputs = true` | **COUNT** |

CloudWatch metrics and sampled requests are enabled on the web ACL and every rule.

**Excluded by design (cost/scope):** no premium/paid managed groups, no Bot Control, no
CAPTCHA, no Challenge action, and no WAF logging configuration.

### Initial COUNT mode and the transition to BLOCK

As delivered, every rule starts in **COUNT** mode: the managed groups use
`override_action { count {} }` and the rate-based rule uses `action { count {} }`. Matched
requests are counted and labeled but **never blocked** — the only non-count disposition is the
web ACL `default_action = allow`. Mode is controlled per rule by `waf_common_rule_set_mode`,
`waf_rate_based_rule_mode`, and `waf_known_bad_inputs_mode` (each `Count_Mode` by default,
switchable to `Block_Mode` with no module edit):

- `Count_Mode` → managed group `override_action { count {} }` / rate rule `action { count {} }`
- `Block_Mode` → managed group `override_action { none {} }` (each rule applies its *own*
  action, not a blanket block) / rate rule `action { block {} }`

**Criteria for transitioning a rule to BLOCK:** evaluate the per-rule CloudWatch metrics,
sampled-request view, and WAF labels over a defined observation window (for example, **7 days**
of representative DEV traffic). Transition a rule only once the measurable condition —
**zero false-positive matches observed over that window** — is met; then flip that rule's
`*_mode` to `Block_Mode`. The Common Rule Set and the rate-based rule are the rules intended to
move to BLOCK after evaluation.

---

## 4. AWS CloudTrail

When `enable_cloudtrail = true` **and** `reuse_existing_trail = false`, the module creates one
**management-events-only** trail and its backing S3 bucket.

- **Reuse-first strategy.** Before creating a trail, confirm whether a suitable existing
  account/organization trail already provides coverage. A trail is reusable **only when both**
  hold: (1) configuration coverage — a multi-region trail including management events, verified
  with `aws cloudtrail describe-trails`; and (2) active logging — `IsLogging = true`, verified
  with `aws cloudtrail get-trail-status`. A configured-but-stopped trail is **not** reusable. If
  a suitable trail exists, set `reuse_existing_trail = true` and no trail is created.
- **Event History limits.** AWS always provides CloudTrail **Event History** (last 90 days,
  management events only, not delivered to a durable bucket) without any configured trail. The
  optional trail adds durable S3 delivery with bounded retention; it does not replace or disable
  Event History.
- **S3 storage, encryption, retention.** The trail bucket has all four Block-Public-Access
  settings enabled, **SSE-S3 (AES256, AWS-managed)** encryption (no customer-managed KMS key),
  **log file validation** enabled, and a lifecycle rule expiring objects after
  `cloudtrail_retention_days` (default **365**, bounded so nothing is retained indefinitely). A
  least-privilege bucket policy grants `cloudtrail.amazonaws.com` only `s3:GetBucketAcl` and
  scoped `s3:PutObject`, conditioned on `aws:SourceArn`/`aws:SourceAccount` (no hardcoded
  account id).
- **Excluded:** no data events, no CloudTrail Insights, no CloudTrail Lake, no CloudWatch Logs
  delivery.

---

## 5. ECR image scanning

- **Implemented (Backend module):** the application ECR repository already has basic
  `scan_on_push = true` — repository-level scanning that runs automatically on image push at
  **no extra charge**. The Security module does **not** duplicate or modify this.
- **Deferred:** Amazon Inspector **enhanced scanning** is an **account-level, billable**
  capability and is **not** enabled. `enable_inspector_enhanced` exists only as a default-off
  gating surface for a future environment.

---

## 6. EventBridge security-event detection and SNS notifications

When `enable_security_alerts = true`, the module creates targeted EventBridge rules on the
**default** event bus plus one SNS topic; `enable_security_alerts` gates both (the detector and
its delivery path).

**Security-event flow:** security-relevant AWS API call → recorded by an active CloudTrail
trail → delivered to the default EventBridge bus → matched by a narrow rule → published to the
SNS security-alerts topic → emailed to a confirmed subscriber.

EventBridge rules (narrow `detail-type = "AWS API Call via CloudTrail"` patterns, specific
`eventSource` + `eventName`, never catch-all):

| Rule | Monitors |
| --- | --- |
| `…-iam-changes` | IAM policy/permission changes (Put/Attach/Detach user/group/role policy, Create/Delete policy, Create/Delete policy version) |
| `…-sg-changes` | Security group ingress/egress authorize + revoke |
| `…-cloudtrail-changes` | `StopLogging`, `UpdateTrail`, `DeleteTrail` |

- **Active-trail dependency.** These rules match CloudTrail-delivered API events, so they only
  fire when a suitable **active** trail delivers management events to the default bus — either a
  reused existing trail (`IsLogging = true`) or the module's new trail (`enable_cloudtrail = true`).
  Without an active trail the rules never match. The module does not auto-enable CloudTrail, and
  `reuse_existing_trail = true` does not by itself guarantee logging.
- **SNS topic + policy.** One `aws_sns_topic` (`…-security-alerts`). Its topic policy is
  least-privilege: `SNS:Publish` for only `events.amazonaws.com`, scoped by `aws:SourceAccount`
  and an `ArnLike aws:SourceArn` on this account/region's `…:rule/*` (the wildcard avoids a
  circular dependency with the rule ARNs while still restricting the publisher). No SSE-at-rest
  (the AWS-managed SNS key cannot support service-to-topic encrypted publish); TLS protects
  data in transit and payloads carry only event text (no secrets).
- **Email subscription + confirmation.** An email subscription is created **only** when
  `security_alerts_email` is non-empty; otherwise the topic exists with no subscription. An SNS
  email subscription starts in **`PendingConfirmation`** — AWS emails a confirmation link that
  the recipient **must click** before any notification is delivered.
- **Excluded:** no Lambda, no custom event bus, no scheduler, no archive/replay/pipe.

---

## 7. Jenkins integration — PLANNED, not implemented

> The following is a **plan** for the future Jenkins CI/CD work. **None of it is implemented**
> by this module or anywhere in the current Terraform. It is documented here only to describe
> intended future behavior.

- **ECR scan-finding gate (planned).** A future Jenkins pipeline stage would, after pushing an
  image, query the basic scan results, compare finding severity against a configurable
  threshold, and **fail the stage** when one or more findings are at or above that threshold.
- **Results-availability guard (planned).** If scan results are not available within **300
  seconds** of the push, the stage would fail and surface a "results unavailable" indication
  rather than deploying.

These are design intentions for a later CI/CD spec; this module creates no Jenkins resources.

---

## 8. DEV cost, toggles, validation, and future hardening

### Estimated DEV monthly cost

The **"$0 baseline"** refers only to this module's **additional** resources when all its
toggles are off; it does not claim the whole environment is free (existing NAT Gateway, ECR,
CloudWatch, etc. retain their own costs, unaffected by this module). Figures below are
approximate `us-east-1` planning estimates, **not a quote**, and apply only **when a capability
is enabled**:

| Capability (enabled) | Approx. monthly | Varies with |
| --- | --- | --- |
| WAF web ACL | ~$5/ACL + ~$1 per active rule + ~$0.60 / million requests | request volume, rule count |
| CloudTrail (new trail) | first mgmt-events copy free; small S3 storage | log/storage volume |
| EventBridge (default bus) | AWS/CloudTrail event matching effectively free | event volume (downstream SNS) |
| SNS | first 1,000 email notifications/month free, then nominal | notification volume |
| Detective services (GuardDuty/Config/Security Hub/Inspector enhanced) | deferred — $0 (not enabled) | n/a |

### Cost controls

All optional billable features default OFF; WAF managed groups and the rate rule start in
COUNT; no customer-managed KMS key is created; WAF logging and CloudTrail data events are
excluded; detective services are deferred.

### Security validation procedures used

- `terraform fmt -check -recursive` on the module and DEV root (formatting).
- `terraform validate` on the composed DEV root (configuration validity).
- `terraform plan` review confirming: zero Security resources at the default posture; exactly
  one CloudFront distribution (no duplicate); one ECR `image_scanning_configuration`; no
  unrestricted all-protocol egress; and no unexpected change/replace/destroy.
- Git-diff secret scan confirming no credentials, tokens, or MongoDB URIs are introduced.

### Future production-hardening recommendations

- After false-positive evaluation, move WAF rules from COUNT to BLOCK via the `*_mode` inputs.
- Add a custom viewer domain with Route 53 + an ACM certificate in `us-east-1` (Edge module).
- Enable the deferred detective services (GuardDuty, AWS Config, Security Hub, Inspector
  enhanced scanning) with their cost implications reviewed.
- Introduce a customer-managed KMS key to encrypt the SNS topic at rest (with an explicit key
  policy granting the EventBridge principal), replacing the DEV TLS-in-transit-only posture.
- Widen CloudTrail (data events, longer retention) and add WAF logging to a dedicated
  destination if request-level forensics are required.
- Add the planned Jenkins ECR scan-finding deployment gate.
