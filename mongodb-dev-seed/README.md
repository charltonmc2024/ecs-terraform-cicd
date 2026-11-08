# mongodb-dev-seed — Offline Synthetic Dataset Generator

Generates an **entirely synthetic** development dataset for the two LMS
databases, for a future **controlled** import into a **personal** MongoDB Atlas
development cluster.

- `teacher_student_db`
- `admin_staff_mongodb`

This tool is **offline only**. It has **no MongoDB/Atlas connection, no driver
import, and no write-to-database capability**. It does not include an importer.
It only writes local files you can inspect and later import yourself under an
explicit, separately-approved step.

## What it is NOT

- Not a database client. It never opens a socket or connects anywhere.
- Not an importer. It does not run `mongoimport` or any write.
- Not real data. No records are copied from any team database.
- No usable credentials. Every synthetic account has an empty `password` and a
  clearly-fake, non-resolvable `auth0_user_id` (`auth0|SYNTHETIC-...`). Real
  admin/staff accounts are created later by each application's own startup logic.

## Requirements

- Python 3 standard library only. No `pip install` needed.
  (No `pymongo`, no `bson`, no `pytest`.)

## Dataset (deterministic)

| Entity | Count | Database |
|---|---|---|
| districts | 2 | admin_staff_mongodb |
| schools | 4 | both (same `_id` on each side) |
| teachers | 4 | teacher_student_db (`user_collection`) |
| students | 12 | teacher_student_db (`user_collection`) |
| classes | 4 | teacher_student_db |
| assignments | 8 | teacher_student_db |
| submissions | 24 | teacher_student_db |
| teacher questions | 8 | teacher_student_db (`teacher_questionbank`) |
| global questions | 4 | admin_staff_mongodb (`global_questionbank`) |
| global assignments | 2 | admin_staff_mongodb (`global_assignments`) |

ObjectIds are deterministic: each logical entity derives a fixed 24-hex id from a
SHA-256 of a project salt + kind + key (`objectid.py`). Re-running produces
byte-identical ids, so a future import is **idempotent** (upsert by `_id`, no
duplicates). Cross-database references (schools, class members, assignment /
submission / global-assignment links) use the same ids on both sides.

## Output format

**MongoDB Extended JSON v2 (canonical).** One file per database+collection under
`output/`, e.g. `admin_staff_mongodb.global_assignments.json`, plus
`output/MANIFEST.json` (file names + counts).

- ObjectId → `{"$oid": "<24-hex>"}`
- datetime → `{"$date": "<ISO-8601 Z>"}`

This is the format `mongoimport` consumes directly (one array per file). All
timestamps use a fixed base time, so output never depends on the wall clock.

## Generate (offline)

```
cd ~/ecs-terraform-cicd/mongodb-dev-seed
python3 generate.py
```

Writes `output/<db>.<collection>.json` and `output/MANIFEST.json`. No network.

## Validate (offline)

```
cd ~/ecs-terraform-cicd/mongodb-dev-seed
python3 -m unittest discover -s tests -v
```

The suite checks, with no database connection:

- document counts match the agreed quantities,
- required fields, BSON/JSON types, enum values, and length limits,
- unique constraints (school name/email, class_code, submission
  (student_id, assignment_id), unique global-assignment titles; sparse
  `questionId` left null),
- cross-database references all resolve (districts↔schools↔users, class members,
  assignments→classes, submissions→assignment/student, global
  assignments→global questions),
- deterministic output and stable/idempotent ids,
- no broken S3/MinIO references (image fields are null / empty),
- written files are valid Extended JSON v2 with `$oid`/`$date` wrappers.

## Schema source of truth

`schema.py` duplicates the verified enums, limits and unique-index rules from the
Step 1/Step 2 read-only investigation of the two services. It is a **copy** on
purpose: the generator must not import or depend on either application repo.

## Safety / scope

- Files are created only inside `mongodb-dev-seed/`.
- No Terraform, AWS, Atlas, or application-repo changes.
- No database connection, no import, no writes.
- A future import step (host + DB-name guard verifying the approved Atlas
  cluster before any write) is **not** included here and requires separate
  approval.
