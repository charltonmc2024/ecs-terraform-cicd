# Erudition Solution — MongoDB Atlas Adoption & Terraform State-Bucket Recovery Review

**Mode:** READ-ONLY investigation. No files changed except this report. No Terraform init/plan/apply/destroy run. No AWS or Atlas resources created. Read-only `aws` describe/list calls only.
**Date of AWS audit:** this session. **Account:** `691778449106` (IAM user `CharltonJob24`). **Region:** `us-east-1`.

---

## Executive Summary (read this first)

1. **The AWS account is currently EMPTY.** Read-only audits returned zero S3 buckets, **zero VPCs (not even a default VPC)**, zero NAT gateways, zero ECS clusters, zero ECR repos, zero DynamoDB tables, zero ALBs, zero CloudFront distributions, zero CloudWatch log groups, zero Secrets Manager secrets, zero EIPs, and no `eruditiontx*` IAM roles. The deleted state bucket `eruditiontx-app-ecs-dev-tfstate-691778449106` returns `HeadBucket 404`. **Nothing from a prior apply survives in the account.**

2. **The deleted bucket destroyed the DEV remote state, and there is no local DEV-state backup anywhere in the repo** → the DEV remote state is **unrecoverable**. The good news: because the account is also empty, "empty state vs. real resources" duplication risk (normally the big danger) is effectively **nil for DEV** — a fresh apply will create everything cleanly.

3. **The single biggest conflict is architectural, not infrastructural.** Steering (`product.md`) and specs `02-data` + `07-mongo-dynamo-migration` declare **DynamoDB as the LMS system-of-record** and describe a full MongoDB→DynamoDB migration. The **new decision is the opposite**: keep MongoDB, hosted on **MongoDB Atlas M0**. The application (`eruditiontx-services-mvp`) is **100% MongoDB today** (Motor/Beanie) with **no DynamoDB/boto3 data access in server code**. These documents must be reconciled before implementation.

4. **The backend Terraform module is already Atlas-ready in all the ways that matter:** it supports an optional `app_secret_arn` injected into the ECS task as a secret, ECS runs in private subnets with `assign_public_ip = false`, egress is open so tasks can reach Atlas via the single DEV NAT Gateway (one stable egress IP to allowlist in Atlas). The task **does not** need VPC peering/PrivateLink (M0 doesn't support them anyway).

5. **The application creates its own MongoDB indexes at startup** (`server/connection/database.py` `init_db()`), so index initialization needs **no Terraform and no separate job** — it happens on container boot against Atlas.

---

# PART A — MongoDB Atlas Adoption Review

## A1. Existing architecture: implemented vs. specified

### Module → spec → code status

| Module (`ecs-terraform/modules/`) | Spec | Module code present? | Spec `tasks.md` checkboxes | Status |
|---|---|---|---|---|
| `network` | `01-network` | **Yes** (`vpc.tf`, `igw.tf`, subnets, route tables, `natgw.tf`, `endpoints.tf`, `outputs.tf`, `variables.tf`, `locals.tf`, `versions.tf`) | **All `[x]`** | **Complete** |
| `data` | `02-data` | **Yes** (`dynamodb.tf`, `schema.tf`, `kms.tf`, `backup.tf`, `outputs.tf`, `variables.tf`) | **All `[ ]`** (unchecked) | **Implemented but spec not marked done**; this is the DynamoDB table that the new Atlas decision calls into question |
| `backend` | `03-backend` | **Yes** (`alb.tf`, `ecs.tf`, `ecr.tf`, `iam.tf`, `secrets.tf`, `logs.tf`, `autoscaling.tf`, `outputs.tf`, `variables.tf`) | **0 checked / 39 unchecked** | **Implemented but spec not marked done** |
| `edge` | `04-edge` | **Yes** (`cloudfront.tf`, `s3.tf`, `outputs.tf`, `variables.tf`) | **0 checked / 35 unchecked** | **Implemented but spec not marked done** |
| `cicd` | `05-cicd` | **Empty dir** (no `.tf`) | all `[ ]`; a Phase-1 `Jenkinsfile` note exists | **Not implemented** (Jenkins_Role module still to be written) |
| `observability` | *(no spec)* | **Empty dir** | n/a | **Not implemented; no spec exists** |

**Dev root** `ecs-terraform/envs/dev/main.tf` wires four modules: `network`, `data`, `backend`, `edge` (no `cicd`, no `observability`). So the composed stack today = network + DynamoDB + ECS/ALB/ECR + CloudFront/S3.

**Spec-tracking inconsistency:** `02-data`, `03-backend`, `04-edge` are fully coded in the modules but their `tasks.md` checkboxes are unchecked, while `01-network` is both coded and fully checked. The checkboxes understate real progress — treat the module code, not the checkboxes, as ground truth for what exists.

### Confirmed architecture facts (from code)
- **Network:** `enable_nat_gateway = true` and `enable_vpc_endpoints = true` in `envs/dev/terraform.tfvars`. One NAT Gateway in `public1` (`modules/network/natgw.tf`), S3 + DynamoDB **Gateway** endpoints (`endpoints.tf`). Two public + two private subnets across two AZs.
- **ALB:** internal (`internal = true`), placed in **private** subnets, ingress only from the AWS-managed `com.amazonaws.global.cloudfront.origin-facing` prefix list (`modules/backend/alb.tf`). Plain HTTP listener (TLS terminates at CloudFront).
- **ECS:** Fargate, `awsvpc`, private subnets, `assign_public_ip = false`, egress `0.0.0.0/0` (`modules/backend/ecs.tf`, `alb.tf`). Two least-privilege IAM roles (execution + task) in `iam.tf`.
- **Secrets:** `modules/backend/secrets.tf` + `ecs.tf` support an optional `var.app_secret_arn` (default `null`, `sensitive = true`). When set, it is injected as container secret `APP_SECRET` via the task definition `secrets` block and the **execution role** gets a scoped `secretsmanager:GetSecretValue` + `ssm:GetParameters` policy on exactly that ARN.
- **Edge:** CloudFront with S3-OAC default behavior and `/api/*` → VPC Origin → internal ALB; default `*.cloudfront.net` cert; no ACM/Route53/WAF. (`modules/edge/cloudfront.tf`, `s3.tf`.)
- **Data:** one DynamoDB table `${name_prefix}-app` (PK/SK single-table, GSI1 item-bank, GSI2 reporting), PAY_PER_REQUEST, AES256, PITR toggle. (`modules/data/dynamodb.tf`.)

### Application (`eruditiontx-services-mvp`) — the data source of truth
- FastAPI + **MongoDB via Motor/Beanie**. Server code imports `motor`, `beanie`, `pymongo` across `server/connection/database.py`, `server/repositories/`, models, services, workers.
- **No DynamoDB/boto3 data access in server code.** The only boto-adjacent server import is `server/connection/storage_bucket.py` (MinIO/S3-compatible **object storage**, unrelated to the database). Confirmed by grep of `server/` excluding `.venv`.
- Connection config: `MONGODB_URL` (and `STAFF_ADMIN_MONGO_URL`) env vars, or assembled from `DB_USER/DB_PASSWORD/DB_HOST/...`. A second **`staff_admin`** MongoDB is a first-class, separate connection.
- **Index creation is in the app**: `init_db()` builds `EXPLICIT_INDEXES` (e.g. unique `(student_id, assignment_id)` on `submission_collection`, dedupe keys, question-bank indexes) plus Beanie-model and repository indexes at startup. This is the real "custom MongoDB indexes based on application queries" artifact.
- **`ecs-terraform-cicd/ecs-application` is a static Next.js marketing site** (its `Dockerfile` builds `.next/standalone` and runs `node server.js`), **NOT** an API consumer of the FastAPI backend. Confirmed; matches spec 07 R9.3.

> Note on which app ECS runs: the `backend` module's ECR/ECS is generic (`${name_prefix}-app`, container port 3000 default, health path `/`). Which image it runs (the Next.js `ecs-application` vs. the FastAPI `eruditiontx-services-mvp`) is a deployment choice set by `image_tag` + the CI build. The FastAPI service listens on **8000** (its Dockerfile `EXPOSE 8000`), while `container_port`/health default to **3000** — a mismatch to resolve when the API is the deployed workload (see A8).

## A2. Steering / specification inconsistencies

**CENTRAL CONFLICT — DynamoDB-as-system-of-record vs. MongoDB Atlas.** The following all assume DynamoDB replaces MongoDB and directly contradict the new Atlas decision:

- `.kiro/steering/product.md` → "**DynamoDB is the LMS system-of-record. The platform is migrating the LMS backend application (`eruditiontx-services-mvp`, FastAPI) from MongoDB to DynamoDB for ALL MongoDB-dependent entities**…" and lists Data = DynamoDB only.
- `.kiro/steering/architecture.md` → request path ends "`ECS Fargate → DynamoDB`"; Data module = DynamoDB.
- `.kiro/specs/07-mongo-dynamo-migration/` (requirements/design/tasks) → an entire multi-phase program to move every entity to DynamoDB, repository layer, reservation items, rollups, ETL, write-paused cutover.
- `.kiro/specs/02-data/` → single DynamoDB table as the storage system-of-record.
- Steering files injected at session root (`terraform.md`, `conventions.md`, `aws-security.md`, `product.md`, `architecture.md`) repeatedly cite DynamoDB outputs/табle as the data layer.

**Other inconsistencies found:**

- **Missing steering files.** The original task referenced `.kiro/steering/tech.md` and `structure.md`. **Neither exists.** Present steering files are exactly: `architecture.md`, `aws-security.md`, `cicd.md`, `conventions.md`, `product.md`, `terraform.md`.
- **Spec numbering gap / missing observability spec.** Specs jump `05-cicd` → `07-mongo-dynamo-migration` with **no `06`**. There is an `observability` **module directory** (empty) but **no observability spec**. `product.md`/`architecture.md` both describe observability responsibilities with nothing specced.
- **CICD "DynamoDB lock table" error.** `05-cicd/tasks.md` task 1.3 and task 2.1 say Jenkins needs "the S3 state bucket **+ DynamoDB lock table**." The actual bootstrap uses **S3 native locking** (`use_lockfile = true` in `backend.config`) and creates **no DynamoDB lock table** (`bootstrap/main.tf`, `bootstrap/README.md`). The Jenkins IAM policy spec would grant permissions on a lock table that does not exist.
- **Backend task-role scope is DynamoDB-only.** `modules/backend/iam.tf` grants the task role `dynamodb:GetItem/PutItem/UpdateItem/Query/TransactWriteItems`. For a MongoDB-Atlas workload the task role needs **no DynamoDB access**; it needs the *execution* role to read the Atlas connection-string secret (already supported) and nothing data-plane for the task role.
- **Spec-07's own internal note is now stale.** It states remote state "**not yet bootstrapped**… `HeadBucket 404`." That observation is *currently* true, but spec-07 frames it as "never bootstrapped," whereas the state history (serial-58 backup) shows the bucket **was created and later destroyed** (see Part B).

## A3. Changes needed to adopt MongoDB Atlas M0 for DEV

### How ECS Fargate tasks reach Atlas (explicit constraints)
- **M0 free tier does NOT support VPC peering or AWS PrivateLink.** Connectivity is **public internet to Atlas SRV hosts over TLS on port 27017**, gated by an **Atlas IP Access List**. **VPC Gateway/Interface endpoints do not help** (Atlas is not an AWS service API).
- Current DEV network already provides the correct path: private-subnet ECS tasks (`assign_public_ip = false`) egress through the **single NAT Gateway**, which presents **one stable Elastic IP**. **Allowlist that one NAT EIP in Atlas** → secure, least-open access.
  - Alternative (NOT recommended): public-subnet tasks with public IPs → rotating IPs force `0.0.0.0/0` in the Atlas allowlist = far less secure. Keep tasks private.
- Atlas connection string uses `mongodb+srv://`. The app's `server/connection/database.py` `_uri_is_encrypted()` treats `mongodb+srv` as **TLS-by-default**, so Atlas connections satisfy the app's TLS gate with no extra flags.

### Secret wiring (already supported by the backend module)
1. Create the Atlas connection string secret **outside Terraform** (AWS Secrets Manager), e.g. `eruditiontx-app/ecs-dev/mongodb-uri`. (Do NOT commit it; do NOT create it in this review.)
2. Pass its ARN to the backend module via `var.app_secret_arn` (surface a dev-root variable → `module "backend"`). Mark sensitive (already is).
3. The module then: injects it as container secret via the task-definition `secrets` block (`ecs.tf` `local.container_secrets`), and attaches the scoped read policy to the **execution role** (`secrets.tf`). Execution role resolves `secrets` at task start.
4. **App env mapping:** the app reads `MONGODB_URL` (and `STAFF_ADMIN_MONGO_URL`). The current module injects a single secret named **`APP_SECRET`**. To feed the app you must either (a) rename the injected env key to `MONGODB_URL`, or (b) support multiple secrets (main + staff-admin). This is a small, intended extension point — see A8 file list.

### What does NOT change
- No VPC peering/PrivateLink/endpoints for Atlas. Keep the existing NAT + Gateway-endpoints design.
- Keep ALB internal, keep ECS private, keep CloudFront as the only public entry.

## A4. DynamoDB implications — retain vs. remove

**Finding:** DynamoDB is used **nowhere in application code** — it exists only in Terraform (`modules/data`), steering, and specs `02-data`/`07`. The app is MongoDB-only. So DynamoDB is **not required by the running application** under the Atlas decision.

**Do NOT assume removal.** Options and trade-offs:

- **Option 1 — Keep `modules/data` but NOT as system-of-record (recommended short term).**
  - *Pros:* zero destructive change; module is complete and valid; near-zero cost (PAY_PER_REQUEST idle table ≈ \$0 + minimal storage; PITR adds small cost — can disable in dev). Preserves the 02-data work and keeps a future option open.
  - *Cons:* steering/specs still imply DynamoDB is the datastore → ongoing documentation drift; the backend task role carries unused DynamoDB permissions (minor least-privilege smell).
  - *State impact:* table never existed in the live account (audit shows zero tables) and the DEV state is gone, so retaining is purely a config decision with **no state-migration hazard**.

- **Option 2 — Remove `modules/data` and the DynamoDB wiring; update steering/specs to MongoDB-Atlas.**
  - *Pros:* architecture, steering, specs, and code all tell one story; backend task role drops DynamoDB permissions (cleaner least privilege).
  - *Cons:* larger documentation/spec rewrite (`02-data`, `07`, `product.md`, `architecture.md`); discards completed `02-data` work; must also drop `module.data` from `envs/dev/main.tf` and the dynamodb outputs, and remove `dynamodb_table_name/arn` inputs to `module.backend`.
  - *State impact:* because the table is **not** in any live state (account empty, DEV state lost), removal is **safe** — there is no `aws_dynamodb_table` in state to destroy. If the table *had* been in the now-lost state, Terraform would simply no longer manage it; the real table (if any) would be orphaned — but the audit shows **no table exists**, so this is moot.

**Recommendation:** For the immediate goal (deploy DEV on Atlas), take **Option 1** to avoid a destructive detour, but **immediately correct the steering/spec narrative** so DynamoDB is described as "retained, not the system-of-record" (or explicitly deprecated), and **pause/annotate spec `07`** as superseded by the Atlas decision. Schedule Option 2 as a clean-up once Atlas is deployed and verified. Either way, update `product.md`/`architecture.md` so the datastore story is unambiguous.

## A5. Remaining tasks in priority order (to a deployable DEV on Atlas)

1. **Reconcile the datastore decision in docs** — update `product.md`, `architecture.md`; annotate `02-data` and `07-mongo-dynamo-migration` as superseded/retained-only. (Blocks nothing technically but prevents re-introducing DynamoDB assumptions.)
2. **Recreate remote state** — run `bootstrap` to recreate the S3 state bucket (Part B4/B5). Harden `force_destroy`.
3. **Provision Atlas M0 manually** (Atlas console, AWS `us-east-1` if offered) and create DB users; capture the SRV connection string **out of band**.
4. **Create the Atlas-URI secret in Secrets Manager** (manual/CLI, not committed) and wire `app_secret_arn` + env-key mapping into the backend module.
5. **Resolve app port/health mismatch** (FastAPI 8000 vs. defaults 3000/`/`) if the API is the deployed workload; set `container_port`, `health_check_path` to the API's real health endpoint.
6. **`terraform init -reconfigure` the dev root** against the recreated bucket; **plan** and review (expect all-create).
7. **First-image bootstrap**: build/push a real image to ECR, then raise `desired_count`/`min_capacity` from 0 → 1 with the real `image_tag` (per `envs/dev` bootstrap comments).
8. **After the task is live, add the NAT EIP to the Atlas IP Access List** (circular bootstrap: the EIP only exists after apply; allowlist it then).
9. **Implement `05-cicd`** (Jenkins_Role module + Jenkinsfile phases); fix the DynamoDB-lock-table error to S3 native locking.
10. **Author an observability spec** (there is a module dir but no spec) if observability is in scope for DEV.

## A6. Expected AWS cost drivers (DEV)

Likely always-on / dominant first:
- **NAT Gateway** — hourly charge + per-GB data processing. **The dominant always-on DEV cost** and the one that matters most for Atlas (all Atlas traffic traverses it). Single NAT (non-AZ-redundant) is the right DEV tradeoff.
- **Application Load Balancer** — hourly + LCU.
- **ECS Fargate** — per vCPU/GB-hour while tasks run (DEV starts at `desired_count = 0`, so ~\$0 until first image).
- **CloudFront** — request + egress (low in DEV).
- **CloudWatch Logs** — storage; retention is capped (`log_retention_days = 14`).
- **DynamoDB** — if retained: PAY_PER_REQUEST idle ≈ \$0 + tiny storage; **PITR** adds small cost (toggle off in dev to save).
- **S3** (frontend + state bucket) — negligible.
- **MongoDB Atlas M0** — **\$0** (free tier) — not an AWS cost.
- **Gateway VPC endpoints (S3/DynamoDB)** — **no hourly charge** (Gateway endpoints are free; only Interface endpoints bill hourly). These actually *reduce* NAT per-GB cost for S3/DynamoDB traffic.

**Lowest-cost secure DEV recommendation:** Keep the **single NAT Gateway** (required for the stable Atlas egress IP and ECR/CloudWatch/STS pulls) — do **not** go NAT-less, because private tasks still need outbound for image pulls and Atlas. Keep Gateway endpoints (free, cut NAT data cost). Keep DynamoDB PITR **off** in dev if the table is retained. Keep Fargate at 0 tasks until an image exists. This is already essentially how the config is set.

## A7. Recommended deployment sequence (Atlas provisioned manually first)

1. Provision **Atlas M0** manually (console), create DB user + database, note the SRV URI.
2. **Bootstrap** the Terraform state bucket (Part B5).
3. Create the **Atlas-URI secret** in Secrets Manager (manual, uncommitted).
4. Decide DynamoDB retain/remove (A4) and update docs.
5. `terraform init -reconfigure` dev root → `plan` (expect all-create) → **operator-reviewed** `apply`.
6. **Build + push** the real application image to ECR (first-image bootstrap).
7. Raise `desired_count`/`min_capacity` to 1 with the real `image_tag`; apply.
8. **Add the NAT Gateway EIP to the Atlas IP Access List.**
9. Verify through **CloudFront** (not the internal ALB directly).
10. Implement CI/CD (`05-cicd`) and observability afterwards.

## A8. Files needing updates (checklist only — no edits made)

**Steering**
- `.kiro/steering/product.md` — remove/replace "DynamoDB is the LMS system-of-record / migrating MongoDB→DynamoDB"; state MongoDB Atlas (M0 for dev) as the datastore; adjust the request-path diagram.
- `.kiro/steering/architecture.md` — change request path tail `… → DynamoDB` to MongoDB Atlas; reframe the Data module.
- *(Consider adding the referenced-but-missing `tech.md` / `structure.md` if the team wants them; they do not exist today.)*

**Specs**
- `.kiro/specs/02-data/` (requirements/design/tasks) — reframe as "retained DynamoDB (not system-of-record)" or deprecate.
- `.kiro/specs/07-mongo-dynamo-migration/` — mark **superseded** by the Atlas decision (do not delete; the user said do not delete specs).
- `.kiro/specs/05-cicd/tasks.md` — fix "DynamoDB lock table" → S3 native locking (`use_lockfile`); confirm Jenkins IAM has no lock-table permission.
- *(New)* an **observability spec** under `.kiro/specs/` (currently only an empty module dir).

**Terraform**
- `ecs-terraform/envs/dev/variables.tf` + `main.tf` — add `app_secret_arn` (and optional staff-admin secret) dev-root variable and pass into `module "backend"`.
- `ecs-terraform/modules/backend/ecs.tf` / `secrets.tf` — map the injected secret env key to `MONGODB_URL` (and optionally `STAFF_ADMIN_MONGO_URL`) instead of the generic `APP_SECRET`.
- `ecs-terraform/modules/backend/variables.tf` + `envs/dev/*` — set `container_port`/`health_check_path` for the FastAPI workload (8000 + real health path) if the API is deployed.
- `ecs-terraform/modules/backend/iam.tf` — if DynamoDB is removed (A4 Option 2), drop the task-role DynamoDB policy.
- `ecs-terraform/bootstrap/main.tf` — set `force_destroy = false` (hardening; see B4).
- If removing DynamoDB: `envs/dev/main.tf` (`module "data"`, dynamodb inputs to backend), `envs/dev/outputs.tf` (dynamodb outputs), `modules/data/*`.

**App config (do NOT change app code now — informational)**
- `eruditiontx-services-mvp/Dockerfile` — currently `COPY .env.qa .env` bakes an env file into the image (secrets-in-image smell). For Atlas on ECS, provide `MONGODB_URL` via the Secrets Manager injection path instead of a baked `.env`.
- `eruditiontx-services-mvp/.env.example` — documents `MONGODB_URL`, `STAFF_ADMIN_MONGO_URL`, `MONGODB_TLS*` — the keys the ECS secret must supply.

---

# PART B — Terraform Backend / Deleted State-Bucket Recovery

## B1. Backend configuration (and confirmation the deleted bucket is still referenced)

- **Dev root backend** `ecs-terraform/envs/dev/backend.tf`: partial config — `terraform { backend "s3" {} }` (filled at init via `-backend-config`).
- **`ecs-terraform/backend.config`** (untracked/gitignored; only `backend.config.example` is git-tracked) names the **deleted** bucket:
  ```
  bucket       = "eruditiontx-app-ecs-dev-tfstate-691778449106"
  key          = "ecs-dev/terraform.tfstate"
  region       = "us-east-1"
  use_lockfile = true
  encrypt      = true
  ```
- **Dev backend cache** `envs/dev/.terraform/terraform.tfstate` records the root was initialized against **that same bucket/key** (`"bucket": "eruditiontx-app-ecs-dev-tfstate-691778449106"`, `"key": "ecs-dev/terraform.tfstate"`, S3 backend).

**Confirmed:** the deleted bucket is still referenced by both `backend.config` and the dev `.terraform` cache. **S3 native locking** is configured (`use_lockfile = true`) — **no DynamoDB lock table** is used anywhere.

## B2. Separate bootstrap config for the state bucket?

**Yes** — `ecs-terraform/bootstrap/` creates it:
- `bootstrap/main.tf`: `aws_s3_bucket.tfstate` named `${app_name}-${environment}-tfstate-${account_id}` → **`eruditiontx-app-ecs-dev-tfstate-691778449106`**, with **versioning Enabled**, **AES256 SSE**, **full public-access block**, and **`force_destroy = true`**. Uses **local state intentionally** (comment: it bootstraps remote state for others). Outputs `state_bucket_name`.
- `bootstrap/README.md` documents the one-time flow and warns that `terraform destroy` here deletes the backing store for every environment and, with `force_destroy = true`, "would delete state objects without warning."

## B3. Does state exist locally/remotely, and is it recoverable?

**Bootstrap LOCAL state** (`bootstrap/terraform.tfstate`):
- **CURRENT** = serial **64**, `resources: []`, no outputs → **EMPTY**.
- **BACKUP** (`bootstrap/terraform.tfstate.backup`) = serial **58**, contains the **fully-created bucket** (`aws_s3_bucket.tfstate`, versioning, SSE, public-access block) + both outputs, same `lineage`.
- **Interpretation (confirmed):** the bucket was created and managed (serial 58), then **removed from bootstrap state between serial 58 and 64** — consistent with a **`terraform destroy` of bootstrap**. With `force_destroy = true`, that destroy deletes the bucket **and all versioned state objects inside it**. The AWS audit (zero buckets, `HeadBucket 404`) corroborates the bucket is gone.

**DEV remote state** (`ecs-dev/terraform.tfstate`): lived **inside the deleted bucket**. I searched the whole repo for any local DEV-state copy/backup and found **none**:
- No tracked `*.tfstate` (`git ls-files | grep tfstate` → empty).
- `ecs-terraform/modules/terraform.tfstate` exists but is serial **1**, `resources: []`, different lineage → **empty/stray**, NOT the DEV state.
- `envs/dev/.terraform/terraform.tfstate` is only the **backend config cache**, not a state with managed resources.
- `envs/dev/.terraform-ci/` contains only `modules/` + `providers/` cache dirs (no state).

**Conclusion:**
- **Bootstrap state** is recoverable in the sense that it is intact locally but **currently empty** (serial 64) — it describes nothing to recover.
- **DEV remote state is UNRECOVERABLE** from S3 (bucket + versions destroyed) and has **no local backup**. Treat DEV state as lost.
- **Mitigating fact:** the account is empty (no DEV resources exist), so a lost-state situation here does **not** mean orphaned infrastructure for DEV.

## B4. Safely recreating the S3 backend — options, trade-offs, hardening

**(a) Re-run bootstrap `terraform apply` to recreate the bucket.**
- Bucket name is **deterministic** (`…-tfstate-691778449106`), so it reuses the same name → `backend.config` stays valid.
- Because bootstrap state is empty (serial 64), apply will try to **CREATE the bucket fresh**. The audit shows the bucket does not exist (`HeadBucket 404`), so creation should succeed.
- **Caveat:** if the name still existed in S3 (globally), apply would fail with `BucketAlreadyOwnedByYou`/`BucketAlreadyExists`. Not the case now, but re-verify at run time.

**(b) Hardening recommendations (recommend, do not execute now):**
- **Set `force_destroy = false`** (or remove it) in `bootstrap/main.tf` so a future `terraform destroy`/accidental delete cannot silently wipe state again. *(This is the single most important fix — it is what enabled the current data loss.)*
- Keep the existing **versioning + AES256 SSE + full public-access block** (already present and correct).
- Consider an **S3 lifecycle rule to retain noncurrent versions** for a defined window (state history safety) and a **least-privilege bucket policy**.
- **S3 native locking is already configured** (`use_lockfile = true`), so **no DynamoDB lock table is needed** — ignore the `05-cicd` spec's lock-table references.
- Optionally enable **MFA-delete** or an SCP/IAM guardrail to prevent bucket deletion.

## B5. Correct Terraform init sequence (before deploying)

1. `cd ecs-terraform/bootstrap && terraform init && terraform apply` — recreate the state bucket. (First apply hardening in B4 if adopted.)
2. **Confirm** the `state_bucket_name` output equals the `bucket` in `ecs-terraform/backend.config` (`eruditiontx-app-ecs-dev-tfstate-691778449106`).
3. `cd ../envs/dev && terraform init -reconfigure -backend-config=../../backend.config` — initialize the dev root against the recreated backend.
4. Because the old DEV remote state is lost, the dev root initializes **EMPTY** → the next `terraform plan` proposes **CREATING all DEV infrastructure**. **This is the point of danger** (B6) *in the general case* — but see B6: the account is empty, so here it is expected and safe.

## B6. Do AWS resources already exist despite the missing state bucket?

**Audit performed (read-only, credentials available as `CharltonJob24`):**

| Check | Command | Result |
|---|---|---|
| S3 buckets | `s3api list-buckets` | **none** |
| State bucket | `s3api head-bucket …tfstate-691778449106` | **404 Not Found** |
| VPCs (all, incl. default) | `ec2 describe-vpcs` | **none** (no default VPC either) |
| NAT gateways | `ec2 describe-nat-gateways` | **none** |
| Elastic IPs | `ec2 describe-addresses` | **none** |
| ECS clusters | `ecs list-clusters` | **none** |
| ECR repos | `ecr describe-repositories` | **none** |
| DynamoDB tables | `dynamodb list-tables` | **none** |
| ALBs | `elbv2 describe-load-balancers` | **none** |
| CloudFront | `cloudfront list-distributions` | **none** |
| CloudWatch log groups | `logs describe-log-groups` | **none** |
| Secrets Manager | `secretsmanager list-secrets` | **none** |
| IAM roles `eruditiontx*` | `iam list-roles` | **none** |

**Conclusion:** Despite prior apply activity (serial-58 bootstrap backup + saved `tfplan` files in both `bootstrap/` and `envs/dev/`), **no DEV application resources currently exist in the account.** The earlier infrastructure appears to have been fully torn down along with the state bucket.

**Implication for apply:** The normal hazard — "applying against empty state while real resources exist → duplicates or `…AlreadyExists` collisions" — **does not apply to DEV here** because the account is empty. A fresh apply after re-init is expected to be **all-create with no collisions**. **No `terraform import` is required for DEV.**

> I verified this via live read-only calls this session. I did **not** audit every region (checks were `us-east-1`, the configured region) or every service; a cheap belt-and-suspenders step before apply is a quick console/Cost-Explorer glance for stray resources in other regions. If credentials had been unavailable, the required manual pre-apply audit would be exactly the table above (derive names from `${app_name}-${environment}` = `eruditiontx-app-ecs-dev-*`).

**Saved plan files** (`bootstrap/tfplan`, `envs/dev/tfplan`) are stale artifacts from prior planning. **Do not apply them** — they reference the old (lost) state and possibly the old bucket. Regenerate plans after re-init. (These are gitignored per conventions; leave them untouched.)

---

# Combined Deployment Readiness & Recommended Sequence

A single ordered path merging Atlas adoption, state-bucket recovery, and the pre-apply gate. **Operator confirmation required before any apply.**

0. **Decide & document the datastore** (A4): retain DynamoDB "not as system-of-record" (fast path) or remove it; update `product.md`, `architecture.md`, and annotate specs `02-data`/`07` so no DynamoDB-as-datastore assumption remains. Fix the `05-cicd` DynamoDB-lock-table error.

1. **Provision Atlas M0 manually** in the Atlas console (AWS `us-east-1` if offered). Create a database + least-privilege DB user. Record the `mongodb+srv://` URI **out of band** (never commit it).

2. **Recover remote state (bootstrap):**
   - `cd ecs-terraform/bootstrap && terraform init && terraform apply` (recreate the bucket; adopt `force_destroy = false` hardening first — B4).
   - Confirm `state_bucket_name` == `backend.config` bucket (B5 step 2).

3. **Create the Atlas-URI secret** in AWS Secrets Manager (manual/CLI, uncommitted), e.g. `eruditiontx-app/ecs-dev/mongodb-uri` (+ staff-admin if used).

4. **Wire the secret** into Terraform: add `app_secret_arn` dev-root variable → `module "backend"`; map the injected env key to `MONGODB_URL` (and `STAFF_ADMIN_MONGO_URL`) in `ecs.tf`/`secrets.tf`. Set `container_port`/`health_check_path` for the real workload (FastAPI 8000 if the API is deployed).

5. **Re-init the dev root:** `cd ../envs/dev && terraform init -reconfigure -backend-config=../../backend.config`.

6. **Pre-apply gate (B6):** confirm the account is still empty (audit table above). Because it is, expect an **all-create** plan with no imports. If any real resource is found later, **reconcile via `terraform import` before apply** (recommend; do not execute blindly).

7. **Plan & review:** `terraform plan` — verify all-create, 0 destroy/replace, no unexpected resources, no `0.0.0.0/0` ingress, scoped IAM. **Operator reviews before apply.**

8. **Apply** (operator-approved): creates VPC, single NAT (+ EIP), subnets, Gateway endpoints, internal ALB, ECS cluster/service (at `desired_count = 0`), ECR, CloudFront, S3 frontend, (DynamoDB if retained).

9. **First-image bootstrap:** build & push the real application image to ECR; set `image_tag=<git-sha>`, `desired_count=1`, `min_capacity=1`; apply.

10. **Allowlist the NAT EIP in Atlas** (the EIP exists only after step 8) → tasks can now reach Atlas securely.

11. **Index init is automatic:** on container start, the app's `init_db()` creates all MongoDB indexes against Atlas — no Terraform/job needed.

12. **Verify via CloudFront** (`*.cloudfront.net`), never the internal ALB directly.

13. **Then:** implement `05-cicd` (Jenkins_Role + Jenkinsfile) and an observability spec/module.

## Things I could NOT verify / caveats
- Could not run Terraform (`init/plan/apply` all out of scope) — the all-create expectation is reasoned from empty-account + empty-state, not from a live plan.
- AWS audit covered `us-east-1` and the services listed; other regions not exhaustively swept.
- Did not connect to any MongoDB/Atlas or read secret values. The Atlas URI, DB users, and the Secrets Manager secret must be handled out of band.
- The deployed-workload identity (Next.js `ecs-application` vs. FastAPI `eruditiontx-services-mvp`) is a deployment choice not pinned in Terraform; the port/health note in A1/A8 assumes the FastAPI API is the intended ECS workload for an Atlas-backed deployment.

---

### Evidence index (key files cited)
- Bootstrap: `ecs-terraform/bootstrap/main.tf`, `bootstrap/README.md`, `bootstrap/terraform.tfstate` (serial 64, empty), `bootstrap/terraform.tfstate.backup` (serial 58, bucket present).
- Backend wiring: `ecs-terraform/envs/dev/backend.tf`, `ecs-terraform/backend.config`, `envs/dev/.terraform/terraform.tfstate` (cache).
- Dev root: `envs/dev/main.tf`, `variables.tf`, `terraform.tfvars`, `outputs.tf`, `providers.tf`, `versions.tf`.
- Modules: `modules/network/{natgw,endpoints,vpc}.tf`, `modules/backend/{alb,ecs,iam,secrets,logs,outputs,variables}.tf`, `modules/data/{dynamodb,schema}.tf`, `modules/edge/cloudfront.tf`.
- Specs: `.kiro/specs/{01-network,02-data,03-backend,04-edge,05-cicd,07-mongo-dynamo-migration}/`.
- Steering: `.kiro/steering/{product,architecture,aws-security,cicd,conventions,terraform}.md` (no `tech.md`/`structure.md`).
- App: `eruditiontx-services-mvp/server/connection/database.py`, `.env.example`, `Dockerfile`; `ecs-terraform-cicd/ecs-application/Dockerfile` (static Next.js).
