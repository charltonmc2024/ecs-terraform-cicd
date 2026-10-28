# EruditionTX DEV — On-Demand Deployment & Teardown Runbook

Safe, repeatable procedure to stand up the EruditionTX DEV ECS Fargate infrastructure on demand
and tear it down when idle, to avoid the always-on NAT Gateway + ALB cost (~$50/month idle; see §6).

| | |
|---|---|
| Repository | `~/ecs-terraform-cicd` |
| Terraform DEV root | `ecs-terraform/envs/dev` |
| Backend config (from `envs/dev`) | `../../backend.config` → `ecs-terraform/backend.config` |
| AWS profile | `charltonecs` |
| Region | `us-east-1` |
| AWS account | `691778449106` (verify every session) |

> **CONVENTION:** Every `terraform apply`, `terraform destroy`, `docker push`, and any state-mutating
> command in this runbook is marked **DOCUMENTATION ONLY — DO NOT EXECUTE** and requires an explicit
> operator approval checkpoint ( ✋ **APPROVAL REQUIRED** ) before a human runs it. Read-only
> commands (`get-caller-identity`, `validate`, `plan`, `describe-*`) may be run to inform a decision.

> **Bootstrap design (from readiness Tasks 1–3):** the DEV root is designed to apply cleanly with
> `desired_count = 0` / `min_capacity = 0` and `image_tag = "latest"`. Terraform creates the ECS task
> definition and service but launches **zero tasks**, so no ECR image is required for the infrastructure
> bootstrap. The reviewed plan is **53 to add, 0 change, 0 destroy** with all optional Security toggles
> off. Application rollout (a real image + raising task counts) is a **separate** phase.

---

## 1. Pre-deployment checks (read-only)

Run these before any apply. All are read-only.

1. **AWS account & profile**

   ```bash
   aws sts get-caller-identity --profile charltonecs --region us-east-1
   ```
   Confirm `Account = 691778449106`. Abort if it differs.

2. **Remote-state bucket & locking**

   ```bash
   aws s3api head-bucket \
     --bucket eruditiontx-app-ecs-dev-tfstate-691778449106 \
     --profile charltonecs --region us-east-1
   ```
   Confirm the bucket is accessible. Locking uses the S3-native lockfile (`use_lockfile = true` in
   `backend.config`) — there is **no** DynamoDB lock table to verify.

3. **Terraform configuration validation**

   ```bash
   cd ecs-terraform/envs/dev
   terraform init -backend-config=../../backend.config   # initializes S3 backend; downloads providers (network)
   terraform fmt -check -recursive
   terraform validate
   ```
   Expect `fmt -check` to exit 0 and `validate` → "Success! The configuration is valid."

4. **Git working-tree review & reproducible revision**

   ```bash
   git status --short
   git rev-parse HEAD
   ```
   Record the commit SHA you are deploying from. Prefer a clean tree — commit or stash unrelated changes
   first (see the known uncommitted items in §8). Deploying from a known revision makes the environment
   reproducible.

5. **Plan review (resource counts & expected charges)**

   ```bash
   terraform plan -input=false -out=tfplan-dev
   ```
   Expect **53 to add, 0 to change, 0 to destroy** (+1 data-source read). Confirm no replacements/destroys.
   Expected charges once applied: ~$50/month idle (NAT + ALB + 6 alarms), ~$62–65/month with one light
   Fargate task (see §6).

6. **Confirm Security toggles disabled**

   ```bash
   grep -E 'enable_waf|enable_cloudtrail|enable_security_alerts' terraform.tfvars
   ```
   All must read `= false`. Confirm the plan contains zero `module.security` resources and CloudFront
   `web_acl_id` is null.

---

## 2. Infrastructure bootstrap

Commands below are **DOCUMENTATION ONLY — DO NOT EXECUTE** without the approval checkpoint.

1. **Initialize** (if not already):
   ```bash
   # DOCUMENTATION ONLY — DO NOT EXECUTE
   cd ecs-terraform/envs/dev
   terraform init -backend-config=../../backend.config
   ```
   > Note: `init` downloads providers (a network action) and initializes the S3 backend.

2. **Create & review a fresh saved plan:**
   ```bash
   # DOCUMENTATION ONLY — DO NOT EXECUTE
   terraform plan -input=false -out=tfplan-dev
   ```
   Review for: 53 add / 0 change / 0 destroy; no replacements; no unexpected public exposure; security
   resources absent; `desired_count`/`min_capacity` remain 0.

3. ✋ **APPROVAL REQUIRED** — operator confirms the plan, then applies the **saved** plan:
   ```bash
   # DOCUMENTATION ONLY — DO NOT EXECUTE
   terraform apply tfplan-dev
   ```
   Applying the saved plan (not a bare `apply`) guarantees you deploy exactly what was reviewed.

4. **Verify infrastructure (read-only, after apply):**
   ```bash
   terraform output
   aws ec2 describe-vpcs --filters Name=tag:Project,Values=eruditiontx-app --profile charltonecs --region us-east-1
   aws ec2 describe-nat-gateways --profile charltonecs --region us-east-1
   aws elbv2 describe-load-balancers --names eruditiontx-app-ecs-dev-alb --profile charltonecs --region us-east-1
   aws cloudfront list-distributions --profile charltonecs --region us-east-1
   aws ecr describe-repositories --repository-names eruditiontx-app-ecs-dev-app --profile charltonecs --region us-east-1
   aws ecs describe-services --cluster eruditiontx-app-ecs-dev-cluster --services eruditiontx-app-ecs-dev-svc --profile charltonecs --region us-east-1
   ```

5. **Confirm `desired_count = 0` during bootstrap:**
   ```bash
   aws ecs describe-services --cluster eruditiontx-app-ecs-dev-cluster \
     --services eruditiontx-app-ecs-dev-svc --profile charltonecs --region us-east-1 \
     --query 'services[0].desiredCount'
   ```
   Must return `0`. No tasks should be running or pending after bootstrap.

---

## 3. Application deployment (separate phase)

This phase is distinct from the infrastructure bootstrap. **Currently manual**; the Jenkins pipeline
is **planned, not implemented** (see the security README §7) — the steps below are the manual
equivalents a future Jenkins pipeline would automate.

1. **Build & push a Git-SHA-tagged image to ECR** — *manual today; planned Jenkins stage.*
   ```bash
   # DOCUMENTATION ONLY — DO NOT EXECUTE
   SHA=$(git rev-parse --short HEAD)
   ECR_URL=$(terraform output -raw ecr_repository_url)   # from envs/dev
   aws ecr get-login-password --profile charltonecs --region us-east-1 \
     | docker login --username AWS --password-stdin "${ECR_URL%/*}"
   docker build -t "$ECR_URL:sha-$SHA" .
   docker push "$ECR_URL:sha-$SHA"
   ```
   Use an **immutable** `sha-<gitsha>` tag (the repo is `IMMUTABLE`); do not rely on `latest` for a
   controlled deploy.

2. **Confirm the image exists in ECR before launching tasks (read-only):**
   ```bash
   aws ecr describe-images --repository-name eruditiontx-app-ecs-dev-app \
     --image-ids imageTag=sha-$SHA --profile charltonecs --region us-east-1
   ```

3. **Obtain the NAT Gateway public IP (read-only):**
   ```bash
   terraform output -raw nat_public_ip        # from envs/dev
   ```

4. **Add ONLY the NAT /32 to MongoDB Atlas Network Access** — *manual, Atlas console / API, outside Terraform.*
   - Atlas → Network Access → add `<nat_public_ip>/32`. **Do not** add `0.0.0.0/0`.
   - Atlas M0 has no VPC peering/PrivateLink, so this egress-IP allowlist is the connectivity path.

5. **Verify the existing Secrets Manager secret (metadata only — never print the value):**
   ```bash
   aws secretsmanager describe-secret \
     --secret-id eruditiontx-app/ecs-dev/mongodb-uri \
     --profile charltonecs --region us-east-1
   ```
   Confirm it exists and is not scheduled for deletion. **Never** call `get-secret-value` in this runbook.

6. **Update `image_tag`, `desired_count`, `min_capacity`** in `envs/dev/terraform.tfvars`:
   ```hcl
   image_tag     = "sha-<gitsha>"   # the immutable image just pushed
   desired_count = 1
   min_capacity  = 1
   ```
   *(This is an intentional, reviewed tfvars value change at deploy time — not a module/source change.)*

7. **Review & apply a SEPARATE application deployment plan:**
   ```bash
   # DOCUMENTATION ONLY — DO NOT EXECUTE
   terraform plan -input=false -out=tfplan-app
   #   expect: task definition updated (new image), service desired_count 0->1,
   #           autoscaling min_capacity 0->1; no infra destroy/replace
   # ✋ APPROVAL REQUIRED
   terraform apply tfplan-app
   ```

8. **Verify application health (read-only):**
   ```bash
   # ECS task running
   aws ecs describe-services --cluster eruditiontx-app-ecs-dev-cluster \
     --services eruditiontx-app-ecs-dev-svc --profile charltonecs --region us-east-1 \
     --query 'services[0].{desired:desiredCount,running:runningCount,pending:pendingCount}'
   # ALB target health
   TG=$(aws elbv2 describe-target-groups --names eruditiontx-app-ecs-dev-tg \
        --profile charltonecs --region us-east-1 --query 'TargetGroups[0].TargetGroupArn' --output text)
   aws elbv2 describe-target-health --target-group-arn "$TG" --profile charltonecs --region us-east-1
   # CloudWatch Logs
   aws logs describe-log-streams --log-group-name eruditiontx-app-ecs-dev-app \
     --profile charltonecs --region us-east-1 --order-by LastEventTime --descending --max-items 3
   # CloudFront routing (public entry point) — reach the app via the CloudFront domain, NOT the internal ALB
   curl -I "https://$(terraform output -raw cloudfront_domain_name)/health"
   ```
   The internal ALB is not internet-reachable by design; always verify through CloudFront.

---

## 4. Safe teardown (separate, explicitly approved)

Teardown removes the ~$50/month idle cost when the environment is not needed. It is a **deliberate,
approved** operation — never routine/automatic.

**Before teardown:**

1. Confirm no active testing and no application users are relying on the environment.
2. Identify data/resources to retain (see §5): the Atlas cluster/users/data, the Secrets Manager secret,
   the Terraform **state** bucket, and anything you need from the frontend S3 bucket or ECR.
3. Review state and generate a destroy plan (read-only review of the plan):
   ```bash
   # DOCUMENTATION ONLY — DO NOT EXECUTE (plan file generation is safe to review)
   cd ecs-terraform/envs/dev
   terraform plan -destroy -out=tfplan-destroy
   terraform show tfplan-destroy          # review exactly what will be deleted
   ```
4. **What Terraform will delete:** all 53 DEV-root resources — VPC/subnets/routes/IGW, NAT Gateway + EIP,
   ALB/TG/listener, ECS cluster/service/task-def, ECR repo (and its images — see §5), the frontend S3
   bucket (and its objects — see §5), CloudFront distribution + OAC + VPC Origin, CloudWatch log
   group/dashboard/alarms, IAM roles/policies, security groups, S3 Gateway endpoint.
   **What remains (NOT managed by this root):** the Terraform state bucket (bootstrap), the Secrets
   Manager secret, and the external MongoDB Atlas cluster/users/data.
5. **Destroy blockers to check first:**
   - **Frontend S3 bucket** must be empty or Terraform's bucket delete fails. Review/retain objects, then
     empty if appropriate (approved):
     ```bash
     # DOCUMENTATION ONLY — DO NOT EXECUTE
     aws s3 ls s3://eruditiontx-app-ecs-dev-frontend --recursive --profile charltonecs --region us-east-1
     # aws s3 rm s3://eruditiontx-app-ecs-dev-frontend --recursive   (only if you intend to lose assets)
     ```
   - **ECR images** are deleted with the repo (`force_delete` behavior varies) — retain any image you need
     first (re-pushable from a Git SHA, see §7).
   - **CloudFront** disable+delete can take 15–40 min; a destroy may appear to hang while the distribution
     disables. This is normal — do not interrupt.
6. ✋ **APPROVAL REQUIRED** — execute the destroy:
   ```bash
   # DOCUMENTATION ONLY — DO NOT EXECUTE
   terraform apply tfplan-destroy          # or: terraform destroy  (with the same review)
   ```
7. **After the NAT Gateway is removed, clean up the Atlas allowlist** — *manual, Atlas console:* remove the
   old `<nat_public_ip>/32` entry from Atlas Network Access. The next deployment will get a **new** NAT IP
   (see §7), so stale entries should be pruned.

---

## 5. State preservation & data safety (rules)

- **Never** destroy the separate Terraform **bootstrap/state** bucket
  (`eruditiontx-app-ecs-dev-tfstate-...`) as part of normal DEV teardown. It lives in the `bootstrap/`
  config with its own local state and holds the remote state for the DEV root.
- **Never** delete or hand-edit the remote state file (`ecs-dev/terraform.tfstate`).
- **Preserve** S3 state-bucket **versioning** and **locking** (both enabled by bootstrap). Do not disable.
- **Do not** use `terraform state rm`, `terraform state push`, `terraform import`, or any manual state
  edit without a separate, written review and approval.
- **Preserve** the MongoDB Atlas cluster, database users, and data — all external to Terraform; teardown
  must not touch them (only the NAT /32 allowlist entry is pruned, §4.7).
- **Preserve** the existing Secrets Manager MongoDB secret — it is referenced by ARN only and is **not**
  created or destroyed by this root.
- **Terraform-managed S3 frontend assets & ECR images:** these **are** deleted on teardown. Treat them as
  reproducible, not durable: re-upload frontend assets from the build, and re-push container images from a
  Git SHA. Retain anything irreplaceable **before** destroy.
- **Confirming a successful destroy without harming the backend:** after destroy, `terraform show` on the
  DEV root should report no managed resources; the state file key still exists (now empty of resources) in
  the **retained** state bucket. Do not delete the state bucket to "finish" a teardown.
- **Recreating the environment:** from the retained config + state backend, re-run §1–§2
  (`init -backend-config=../../backend.config` → `plan` → approved `apply`). A fresh bootstrap yields a new
  NAT IP (update Atlas, §3.3–3.4) and empty frontend/ECR (re-deploy the app, §3).

---

## 6. Cost controls

Estimates from readiness Task 3 (us-east-1, 730 h/month; planning estimates, not quotes):

| Item | When it bills | Approx. |
|---|---|---|
| **NAT Gateway** (hourly) | immediately on bootstrap, even with 0 tasks | ~$32.85/mo + $0.045/GB data |
| **Application Load Balancer** (hourly + LCU) | immediately on bootstrap | ~$16.43/mo + small LCU |
| **Public IPv4 address** | the NAT EIP is in-use (free while attached); note AWS charges ~$0.005/hr (~$3.6/mo) per public IPv4 — applies to in-use public IPs **(unverified exact applicability to the NAT EIP)** | ~$0–3.6/mo |
| **Fargate** | only when tasks run | ~$9–10/mo per 0.25 vCPU / 0.5 GB task |
| **CloudFront / S3 / ECR / CloudWatch / data transfer** | usage-based | ~$0–few $/mo at light DEV |
| **6 CloudWatch alarms** | once created | ~$0.60/mo |

**Idle floor ≈ $50/month (NAT + ALB + alarms); one light task ≈ $62–65/month.** NAT + ALB are ~98% of
the idle floor, so **teardown when idle** is the main lever.

**Verify no unexpected billable resources remain after teardown (read-only):**
```bash
aws ec2 describe-nat-gateways --filter Name=state,Values=available --profile charltonecs --region us-east-1
aws ec2 describe-addresses --profile charltonecs --region us-east-1          # no lingering/unattached EIPs
aws elbv2 describe-load-balancers --profile charltonecs --region us-east-1
aws ecs list-services --cluster eruditiontx-app-ecs-dev-cluster --profile charltonecs --region us-east-1 2>/dev/null
aws cloudfront list-distributions --profile charltonecs --region us-east-1
```
An **unattached** EIP after teardown would bill (~$3.6/mo) — release it if the NAT was removed but the EIP
lingered.

**Optional AWS Budget alerts (NOT created here):** consider a monthly AWS Budgets alert (e.g. $20 and $75
thresholds) and Cost Anomaly Detection to catch a forgotten NAT/ALB. Creating budgets is out of scope for
this runbook — document the intent only.

**Session checklist:**
- *Start of DEV session:* pre-checks (§1) → approved bootstrap (§2) → (if testing the app) approved app
  deploy (§3) → confirm Atlas allowlist has the current NAT IP.
- *End of DEV session:* if done for a while, run approved teardown (§4) to drop to ~$0; otherwise set
  `desired_count = 0` to drop Fargate (~$10/mo) while keeping infra. Prune stale Atlas allowlist entries.

---

## 7. Risk & recovery

- **Failed / partial `apply`:** re-run `terraform plan` to see the delta, then a fresh approved `apply` to
  converge (Terraform is declarative; a partial apply is resumed by re-applying). Investigate any resource
  stuck "creating" (e.g. CloudFront) before retrying.
- **Failed / partial `destroy`:** most often a non-empty frontend S3 bucket or a still-disabling CloudFront
  distribution. Empty the bucket (approved, §4.5) / wait for CloudFront, then re-run the approved destroy.
- **State-lock problems:** with S3-native locking, a crashed run can leave a lock. Verify no other Terraform
  is running, then clear it deliberately with `terraform force-unlock <LOCK_ID>` **(✋ approval; use the ID
  Terraform prints — never guess)**. Do not delete the lock object by hand.
- **CloudFront provisioning/deletion delays:** create and delete can each take ~15–40 min. Expect `apply`
  and `destroy` to pause on the distribution; do not interrupt.
- **NAT public IP changes between deployments:** each bootstrap allocates a **new** EIP, so the NAT egress
  IP changes. After every fresh bootstrap, update MongoDB Atlas Network Access with the new
  `nat_public_ip` (§3.3–3.4) and prune the old /32 (§4.7), or the app cannot reach Atlas.
- **ECR image loss:** images are deleted with the repo on teardown. They are reproducible — rebuild and
  re-push from the Git SHA (§3.1). Keep the source commit tagged so any image can be recreated.
- **Preventing accidental deletion of persistent data:** persistent data lives **only** in MongoDB Atlas
  (external) and the retained state/secret — none of which this root destroys. Always review the
  `-destroy` plan (§4.3) and confirm it lists only DEV-root infrastructure, never the state bucket or
  secret, before approving.

---

## 8. Readiness assessment & deliverable

**Runbook path:** `ecs-terraform/docs/DEV-ON-DEMAND-RUNBOOK.md`

**Concise sequence:**
- **Deploy:** pre-checks (§1) → `init -backend-config=../../backend.config` → `plan -out=tfplan-dev`
  (53/0/0) → ✋ approve → `apply tfplan-dev` (0 tasks) → [optional app phase: push image → update Atlas /32
  → set image_tag/desired_count/min_capacity → `plan -out=tfplan-app` → ✋ approve → `apply` → verify].
- **Teardown:** confirm idle & retain list (§4.1–4.2) → `plan -destroy -out=tfplan-destroy` → review (§4.4) →
  resolve blockers (empty frontend bucket, wait on CloudFront) → ✋ approve → destroy → prune Atlas /32 →
  verify no billable remnants (§6).

**Explicit approval checkpoints:** before `apply tfplan-dev` (§2.3), before `apply tfplan-app` (§3.7),
before any destroy (§4.6), and before `force-unlock` (§7).

**Readiness: PASS — no BLOCKERS.** Bootstrap applies cleanly with 0 tasks and no image (Tasks 1–2); live
AWS prerequisites all verified (account, state bucket, secret, CloudFront prefix list & managed policies,
Admin permissions, quota headroom); costs quantified (Task 3).

**WARNINGS (operational, not blockers):**
1. **Uncommitted / untracked working tree.** `modules/backend/alb.tf` and `secrets.tf` are modified and
   `modules/security/` + `.kiro/specs/08-security/` are untracked. Deploy from a known, committed revision
   (§1.4) for reproducibility — commit/review these first (separate from this runbook; no commit performed
   here).
2. **Atlas allowlist is manual & NAT-IP-dependent.** Every fresh bootstrap changes the NAT IP; the app will
   not reach Atlas until the new /32 is allowlisted (§3.4, §7).
3. **Secret content not validated.** The secret exists (metadata confirmed) but its URI is intentionally
   unread; a malformed value only surfaces when a task starts (§3.5).
4. **Public IPv4 charge** on the NAT EIP is listed as unverified in §6 — confirm against current billing.

**No required code changes** were identified to make the bootstrap succeed. The optional hardening items
from the 08-security review remain discretionary.

**No unsafe assumptions** are baked into procedures: all apply/destroy/push steps are gated behind explicit
approval, state/secret/Atlas data are protected by the §5 rules, and every command here is documentation
only — nothing in this task deployed or modified anything.
