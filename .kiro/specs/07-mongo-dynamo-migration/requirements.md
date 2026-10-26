# Requirements Document

> **⚠️ SUPERSEDED (2026-10-19).** This specification is retained for historical
> reference only and must NOT be implemented. The project has standardized on
> **MongoDB Atlas (M0 free tier)** as the application's only database; the
> MongoDB→DynamoDB migration described below is cancelled, and the DynamoDB
> Terraform resources it depended on (the `02-data` data module) have been
> removed. For the current data architecture see `.kiro/steering/architecture.md`,
> `.kiro/steering/product.md`, and the `02-data` spec. The content below is left
> unchanged as a record of the previously proposed direction.

## Introduction

This spec defines the full migration of the Erudition Solution LMS backend
(`eruditiontx-services-mvp`, a FastAPI + MongoDB/Beanie service) from MongoDB to
Amazon DynamoDB. DynamoDB becomes the system-of-record for **every** MongoDB-dependent
entity in the LMS, not only the adaptive-testing subsystem. The DynamoDB table itself
is owned by the `02-data` spec/module; this spec owns the application-side data-access
layer, the data-migration (ETL), the search/aggregation replacements, and the cutover.

This spec is **documentation only** at Phase 1. It implements no application code,
provisions no AWS resources, and deletes no data. It does not modify the local Dockerfile
edit in the backend repository, and it does not touch the `aws-production-deployment-course`
reference repository.

### Verified ground-truth facts (checked, not assumed)

- **Terraform remote state (re-verified this session).** Account `691778449106`. The configured
  backend bucket `eruditiontx-app-ecs-dev-tfstate-691778449106` returns `HeadBucket 404`, the
  account currently lists zero S3 buckets, and the state object `ecs-dev/terraform.tfstate`
  returns `HeadObject 404`. The remote state backend is therefore **not yet bootstrapped** as of
  this check. This is a verified fact, re-checked rather than carried over from a prior session.
- **ID shapes are already heterogeneous.** `server/utilities/user_id_helper.py` (`to_user_id`,
  `resolve_user_query`) shows the system already stores BOTH ObjectId-compatible 24-hex strings
  (local JWT users) AND Auth0 subject strings like `auth0|abc123` (Auth0 users). IDs are already
  NOT uniformly 24-hex.
- **ObjectId validation surface (audited).** 30 `ObjectId.is_valid` call sites across 10 files,
  211 `ObjectId(...)` coercions, 94 `PydanticObjectId` fields, and a hard 24-hex regex at
  `server/models/themes.py:337` (`^[0-9a-fA-F]{24}$`) that rejects any non-24-hex id.
- **Operation profile (measured).** `find_one` x117, `aggregate` x33 (`$lookup`/`$facet`/`$group`/
  `$reduce`), `update_one` x25, `$regex` x16, `count_documents` x6, `$sample` x3, `insert_one` x3,
  `update_many` x1; 144 HTTP endpoints; 15 collections; a second `staff_admin` MongoDB; cross-DB
  question banks; S3-compatible MinIO object storage (unrelated to DB scope).

## Glossary

- **Backend**: `eruditiontx-services-mvp`, the FastAPI service being migrated.
- **App_Table**: the single DynamoDB table owned by the `02-data` module.
- **Repository_Layer**: the new application abstraction that hides the datastore behind interfaces.
- **Reservation_Item**: a DynamoDB item used to enforce a uniqueness constraint via a conditional write.
- **ETL**: the one-time export -> transform -> load of MongoDB data into DynamoDB.
- **Write_Paused_Cutover**: a cutover in which all writers are quiesced before the datastore flip.
- **Rollup_Item**: a denormalized aggregate item (counts/sums) maintained at write time.
- **Writer**: any process that mutates data — the API, background workers, importers, admin/staff tools.

## Requirements

### Requirement 1: Complete entity coverage

**User Story:** As a platform engineer, I want every MongoDB-dependent entity migrated, so that no
LMS data or access path is left behind.

#### Acceptance Criteria

1. THE spec SHALL enumerate every MongoDB collection and entity in the Backend and map each to a
   DynamoDB key model, including accounts, users (student/teacher), classes (with embedded roster),
   assignments, submissions, share requests, clients, schools, districts, feature flags, themes/user
   themes, class messages, and all question-bank stores.
2. THE spec SHALL account for the second `staff_admin` MongoDB connection as an in-scope datastore;
   staff/admin data SHALL NOT be omitted from the inventory.
3. THE spec SHALL mark any entity explicitly deferred to a later wave WITH a reason, and SHALL keep
   it in final scope.

### Requirement 2: ID compatibility (existing and new)

**User Story:** As an API consumer, I want entity IDs to remain compatible, so that existing clients
and URLs keep working after migration.

#### Acceptance Criteria

1. THE migration SHALL preserve existing entity IDs as opaque strings; the current string id value
   SHALL remain the externally visible id.
2. THE internal storage-key prefixes (for example `STUDENT#`, `CLASS#`) SHALL NOT appear in API
   responses, URLs, or any externally visible identifier.
3. THE migration SHALL audit ALL ObjectId validation and id-shape assumptions AND SHALL first establish,
   per field, WHICH identifier each field is intended to accept (entity-reference ObjectId vs the
   request `uuid`/`mongodb_id` vs the Auth0 `auth0_user_id`) BEFORE proposing any id-format change.
   Validation SHALL NOT be relaxed merely because Auth0 ids and MongoDB entity ids have different
   formats; entity-reference validators that correctly accept 24-hex (e.g. `server/models/themes.py`
   `theme_id`) SHALL be preserved.
4. WHERE a new id format is adopted for a specific new entity, it SHALL remain an opaque string to
   clients and SHALL be applied ONLY to that entity's own reference fields after confirming no field
   intends to accept a different identifier; user-identifier handling SHALL continue to use the
   mongodb_id string set by the Auth0 bearer.
5. THE migration SHALL keep API request/response id fields byte-compatible for existing entities.

### Requirement 3: Uniqueness via reservation items and transactional conditional writes

**User Story:** As a platform engineer, I want uniqueness enforced correctly on DynamoDB, so that
duplicate emails, class codes, and submissions cannot occur.

#### Acceptance Criteria

1. THE design SHALL enforce email uniqueness and class-code uniqueness using Reservation_Items plus
   transactional conditional writes (`TransactWriteItems` with `attribute_not_exists`), NOT a GSI.
2. THE design SHALL enforce submission uniqueness per `(student_id, assignment_id)` through the item
   key design plus a conditional write, NOT a secondary index (DynamoDB has no unique GSI).
3. IF a uniqueness conditional write fails, THEN the operation SHALL fail cleanly and SHALL NOT create
   a duplicate.
4. THE design SHALL specify how a Reservation_Item is released or updated on legitimate change
   (for example email change, class-code reissue).

### Requirement 4: Search, adaptive sampling, and aggregation replacements

**User Story:** As a platform engineer, I want MongoDB query features replaced without losing
functionality, so that behavior and performance are preserved.

#### Acceptance Criteria

1. THE design SHALL propose replacements for `$regex` text search (16 call sites) and `$facet` facet
   counts, SHALL compare at least an external search engine, precomputed facet/search items, and
   bounded Query+client-filter options, and SHALL compare behavioral parity and operating cost.
2. THE design SHALL NOT select or provision OpenSearch (or any search engine) in this spec; it SHALL
   present a comparison and leave the selection as an explicit open decision.
3. THE design SHALL NOT silently reduce existing search functionality; any proposed reduction SHALL
   be called out explicitly for sign-off.
4. THE design SHALL propose a replacement for `$sample` adaptive/random question sampling that does
   not rely on a DynamoDB feature that does not exist.
5. THE design SHALL replace dashboard `$lookup`/`$group`/`$reduce` aggregations with write-time
   Rollup_Items read by a single Query, with NO read-time joins and NO table Scans.

### Requirement 5: Idempotent, correct rollups

**User Story:** As a platform engineer, I want aggregate rollups to stay correct under edits, deletes,
and regrading, so that dashboards never drift.

#### Acceptance Criteria

1. Rollup_Item updates SHALL be idempotent so a retried or duplicated event does not double-count.
2. THE design SHALL define how a rollup is corrected on submission edit, delete, and regrade (not only
   on first submit).
3. THE design SHALL define the ordering/consistency approach (for example idempotency keys, versioning,
   or conditional increments) that keeps rollups consistent with base items.

### Requirement 6: BatchGet correctness

**User Story:** As a platform engineer, I want cross-item fan-out reads to be correct and bounded, so
that question-bank fetches do not silently drop items.

#### Acceptance Criteria

1. THE design SHALL specify `BatchGetItem` request chunking to respect the 100-key / 16 MB limits.
2. THE design SHALL specify retry handling for `UnprocessedKeys` with backoff.
3. THE design SHALL specify how result ordering is reconstructed when callers depend on input order,
   and SHALL preserve the existing `_MAX_QUESTION_FETCH` bound.

### Requirement 7: Write-paused cutover with separate rollback

**User Story:** As a platform engineer, I want a safe cutover, so that a failure never corrupts data
and rollback is always possible.

#### Acceptance Criteria

1. THE cutover SHALL pause ALL Writers (API, background workers, import jobs, admin/staff services)
   before the datastore flip.
2. THE design SHALL define rollback SEPARATELY for (a) before writes resume and (b) after writes resume.
3. WHERE a zero-write-downtime window is required and dual-writes are considered, THE design SHALL
   explain why, SHALL define partial-failure handling (one store succeeds, the other fails), and SHALL
   define reconciliation; dual-write SHALL be the documented contingency, not the default.
4. THE cutover SHALL NOT delete MongoDB data; MongoDB SHALL be retained through a defined soak period.

### Requirement 8: Migration waves by dependency

**User Story:** As a platform engineer, I want migration ordered by dependency, so that referenced
entities exist before referencing ones.

#### Acceptance Criteria

1. THE design SHALL propose migration waves ordered by data dependency (for example accounts/users and
   schools/clients/districts before classes; classes before assignments; assignments before submissions
   and rollups).
2. THE waves SHALL include staff/admin data and the question-bank stores; none SHALL be left out.

### Requirement 9: Cross-repository coverage

**User Story:** As a platform engineer, I want all consuming repositories identified, so that API
compatibility can be verified across the system.

#### Acceptance Criteria

1. THE spec SHALL list the exact repositories that must be inspected before claiming complete coverage:
   the student/teacher frontend/web client, admin-staff-client, eruditiontx-question-ingest,
   mathmatterstx-services (role unconfirmed), and the API contract/test repository (the `test_reports`
   submodule). THE spec SHALL record which are cloned locally and SHALL report missing access rather
   than claim coverage; none of these are cloned locally as of task 1.4.
2. THE spec SHALL NOT treat unrelated training/bootcamp/beanstalk/EKS repositories as dependencies
   unless evidence shows they consume this API or data.
3. THE static marketing site at `ecs-terraform-cicd/ecs-application` SHALL be recorded as NOT an API
   consumer (verified: no API calls, no id-shape coupling).

### Requirement 10: No-op safety for Phase 1

**User Story:** As a platform engineer, I want Phase 1 to be documentation-only, so that nothing is
changed prematurely.

#### Acceptance Criteria

1. Phase 1 SHALL modify only steering and spec documents; it SHALL NOT modify application or Terraform
   code, provision resources, or delete data.
2. Phase 1 SHALL preserve the Backend's local Dockerfile edit and SHALL leave the course reference
   repository unchanged.
3. THE `02-data` spec SHALL remain focused on storage infrastructure; migration/application concerns
   SHALL live in this spec.

## Out of Scope

Selecting or provisioning a search engine; running ETL; applying Terraform; deleting MongoDB; changing
the application framework; object-storage (MinIO/S3) migration. Actual implementation of any code is
out of scope for Phase 1.
