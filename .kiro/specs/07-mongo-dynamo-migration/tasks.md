# Implementation Plan: 07-mongo-dynamo-migration

> **⚠️ SUPERSEDED (2026-10-19).** This specification is retained for historical
> reference only and must NOT be implemented. The project has standardized on
> **MongoDB Atlas (M0 free tier)** as the application's only database; the
> MongoDB→DynamoDB migration described below is cancelled, and the DynamoDB
> Terraform resources it depended on (the `02-data` data module) have been
> removed. None of the tasks below should be started. For the current data
> architecture see `.kiro/steering/architecture.md`, `.kiro/steering/product.md`,
> and the `02-data` spec. The content below is left unchanged as a record of the
> previously proposed direction.

## Overview

This plan migrates the Erudition Solution LMS backend (`eruditiontx-services-mvp`) from MongoDB to
DynamoDB as the system-of-record for ALL MongoDB-dependent entities. The DynamoDB table resource stays
owned by `02-data`; this spec owns the application data-access layer, uniqueness/key design,
search/aggregation replacements, ETL, and the write-paused cutover.

Phase 1 (tasks under section 1) is DOCUMENTATION ONLY: steering/spec edits and inventories. It changes no
application or Terraform code, provisions nothing, and deletes nothing. The backend's local Dockerfile
edit and the `aws-production-deployment-course` reference repo are preserved. Later phases (2+) are listed
for sequencing but are NOT started in Phase 1.

Verified precondition (re-checked this session, not assumed): the Terraform remote state bucket
`eruditiontx-app-ecs-dev-tfstate-691778449106` returns HeadBucket 404 and the account has zero buckets,
so any 02-data schema apply remains blocked on bootstrap and is out of Phase 1.

## Tasks

- [ ] 1. Phase 1 — documentation only (steering + specs + inventories)
  - [ ] 1.1 Record the full entity inventory and single-table key model
    - Capture every collection/entity (accounts, users, classes+roster, assignments, submissions, share
      requests, clients, schools, districts+feature flags, themes/user themes, class messages, all
      question-bank stores) and the staff_admin datastore; map each to PK/SK
    - Mark any later-wave entity with a reason; keep it in final scope
    - _Requirements: 1.1, 1.2, 1.3_

  - [ ] 1.2 Document the ObjectId / ID-compatibility audit and strategy
    - Record the audit surface: 30 `ObjectId.is_valid` sites (10 files), 211 `ObjectId(...)` coercions,
      94 `PydanticObjectId` fields, the `themes.py:337` 24-hex regex, and the heterogeneous
      ObjectId/Auth0 handling in `user_id_helper.py`
    - State the strategy: preserve existing ids as opaque strings; keep API ids byte-compatible; relax the
      themes 24-hex regex BEFORE adopting any new id format for new entities
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5_

  - [ ] 1.3 Propose targeted steering/spec edits (documentation only)
    - `.kiro/steering/product.md`: record DynamoDB as the LMS system-of-record replacing MongoDB and
      `eruditiontx-services-mvp` as the consuming application
    - Keep `02-data` focused on storage infrastructure; do NOT move its completed task history — add a
      pointer from `02-data` to this spec for migration/application concerns
    - _Requirements: 10.1, 10.3_

  - [x] 1.4 List the exact cross-repositories to inspect
    - Name the real frontend/web client, the admin/staff tool, the question-ingest/importer, and the
      `test_reports` contract-test submodule; record `ecs-application` as NOT an API consumer (verified)
    - Exclude unrelated training/bootcamp/beanstalk/EKS repos unless evidence shows they consume this API
    - _Requirements: 9.1, 9.2, 9.3_

  - [ ] 1.5 Confirm Phase 1 no-op safety
    - Confirm no application/Terraform code changed, nothing provisioned, nothing deleted; the local
      Dockerfile edit and the course repo are untouched
    - _Requirements: 10.1, 10.2, 10.3_

- [ ] 2. Phase 2 — DynamoDB schema design request to 02-data (plan/validate only; no apply)
  - [ ] 2.1 Specify the new GSIs and reservation/rollup item shapes for 02-data to implement
    - GSI-teacher, GSI-assignment-submissions, GSI-question-filter; reservation and rollup item key shapes
    - `terraform fmt`/`validate`/`plan` only; apply is blocked on remote-state bootstrap and is out of scope
    - _Requirements: 3.1, 4.5, 8.1_

- [ ] 3. Phase 3 — Repository_Layer abstraction (no behavior change)
  - [ ] 3.1 Introduce repository interfaces behind the ~15 direct `db[...]` call sites
    - Centralize id parsing/coercion; keep MongoDB as the active backing store
    - _Requirements: 2.3, 2.4_

- [ ] 4. Phase 4 — Query/feature re-implementation on DynamoDB
  - [ ] 4.1 Implement uniqueness via reservation items + transactional conditional writes
    - Email, class-code, and submission `(student_id, assignment_id)` uniqueness; release/update on change
    - _Requirements: 3.1, 3.2, 3.3, 3.4_

  - [ ] 4.2 Implement BatchGet chunking, UnprocessedKeys retry, and input-order reconstruction
    - Respect 100-key/16 MB limits and the existing `_MAX_QUESTION_FETCH` bound; fail loudly on drop
    - _Requirements: 6.1, 6.2, 6.3_

  - [ ] 4.3 Implement idempotent, delta-based rollups for dashboards
    - Handle first submit, edit, delete, and regrade; idempotency keys/versioning; no read-time joins/scans
    - _Requirements: 4.5, 5.1, 5.2, 5.3_

  - [ ] 4.4 Implement the `$sample` adaptive/random-sampling replacement
    - Bounded candidate Query + app-side selection (or random-shard cursor); no non-existent DB feature
    - _Requirements: 4.4_

  - [ ]* 4.5 Produce the search-options comparison and classify each `$regex`/`$facet` site (NO selection)
    - Compare external search engine vs precomputed items vs bounded Query+filter on parity and cost;
      classify all 16 `$regex` + 2 `$facet` sites; do NOT select or provision a search engine; flag any
      functionality reduction explicitly
    - _Requirements: 4.1, 4.2, 4.3_

- [ ] 5. Phase 5 — ETL and parity
  - [ ] 5.1 Build the one-time ETL (export -> transform ids/embeds -> load) and parity tests
    - Dedupe submissions before enforcing uniqueness; parity on heavy read paths; no deletes
    - _Requirements: 1.1, 3.2, 7.4_

- [ ] 6. Phase 6 — Write-paused cutover with separate rollback
  - [ ] 6.1 Execute the write-paused cutover
    - Pause ALL writers (API, workers, import jobs, admin/staff services); final delta ETL; parity; flip
      the datastore config; run the `test_reports` contract suite; resume writers
    - _Requirements: 7.1_

  - [ ] 6.2 Define and rehearse rollback separately for before and after writes resume
    - Before: revert config flag to MongoDB, discard DynamoDB delta. After: bounded reverse-ETL of the
      post-cutover delta; retain MongoDB through a soak period (no delete). Dual-write only as contingency
      with partial-failure handling and reconciliation
    - _Requirements: 7.2, 7.3, 7.4_

- [ ] 7. Phase 7 — MongoDB decommission (DEFERRED; not planned here)
  - [ ] 7.1 Decommission MongoDB after soak and sign-off
    - Explicitly out of scope for this plan; requires separate operator approval
    - _Requirements: 7.4_

## Notes

- Phase 1 is documentation only; it modifies only steering/spec files. No application or Terraform code is
  changed, nothing is provisioned, and no data is deleted.
- The backend's local Dockerfile edit is preserved; `aws-production-deployment-course` is unchanged.
- `02-data` keeps its completed task history and stays focused on storage infrastructure; migration and
  application concerns live in this spec.
- The Terraform remote-state bucket was re-verified absent this session (HeadBucket 404), so any 02-data
  schema apply is blocked on bootstrap and is out of scope here.
- Tasks marked `*` are optional/analysis sub-tasks (e.g. the search comparison), but the comparison itself
  must not select or provision a search engine.
- All MongoDB-dependent entities, including staff/admin, remain in final scope; waves order by dependency.

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "1.2", "1.4"] },
    { "id": 1, "tasks": ["1.3"] },
    { "id": 2, "tasks": ["1.5"] },
    { "id": 3, "tasks": ["2.1"] },
    { "id": 4, "tasks": ["3.1"] },
    { "id": 5, "tasks": ["4.1", "4.2", "4.3", "4.4", "4.5"] },
    { "id": 6, "tasks": ["5.1"] },
    { "id": 7, "tasks": ["6.1"] },
    { "id": 8, "tasks": ["6.2"] },
    { "id": 9, "tasks": ["7.1"] }
  ]
}
```
