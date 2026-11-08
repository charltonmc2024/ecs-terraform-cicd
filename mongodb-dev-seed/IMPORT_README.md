# import_tool — Safe Local Atlas Synthetic-Data Import

Offline-first, safety-gated loader for the synthetic dataset in `output/`.
**Default behavior is offline validation.** Connecting modes are read-only
except the single insert phase of `import`, which is fail-closed behind a
double confirmation and an approved SHA-256 baseline.

This tool does NOT accept a connection URI. It builds the connection in memory
from a fixed username (`eruditiontx_ecs_dev`) and host
(`ecscluster.xoiozdv.mongodb.net`) plus the password read from the
`ATLAS_PASSWORD` environment variable. No password, username, or connection
string is ever printed, logged, or written.

## Requirements

- `bson.json_util` and `pymongo` must be importable for Extended JSON validation
  and for any connecting mode. Validation FAILS CLOSED if `bson.json_util` is
  missing (it will not silently use a weaker parser). Use an interpreter/venv
  that has pymongo installed.

## Modes

Run from `mongodb-dev-seed/`:

```
# 1) Offline validation (DEFAULT) — no network, no password needed
python3 -m import_tool.cli
python3 -m import_tool.cli --mode validate

# 2) Offline integrity — SHA-256 of files vs the approved baseline
python3 -m import_tool.cli --mode integrity

# 3) Read-only preflight — host/TLS, collection allowlist, count_documents({})==0
ATLAS_PASSWORD=... python3 -m import_tool.cli --mode preflight

# 4) Import — INSERT-ONLY, fail-closed; requires BOTH flags, exact phrase
ATLAS_PASSWORD=... python3 -m import_tool.cli --mode import \
    --execute --confirm "IMPORT teacher_student_db,admin_staff_mongodb"

# 5) Read-only verify — counts vs MANIFEST + cross-references
ATLAS_PASSWORD=... python3 -m import_tool.cli --mode verify
```

Provide the password as a one-shot prefix (`ATLAS_PASSWORD=... python3 ...`) and
avoid exporting it; unset it after use.

## Safety model

- Offline default; connecting modes import pymongo lazily so validate/integrity
  never touch the network.
- Host allowlist (only `ecscluster.xoiozdv.mongodb.net`) + denylist of team /
  localhost / private-range hosts.
- Database allowlist (`teacher_student_db`, `admin_staff_mongodb`) and an exact
  10-collection allowlist; any unexpected collection aborts.
- TLS with certificate verification required; insecure TLS options refused.
- `count_documents({}) == 0` empty check for every target collection in
  preflight, plus an immediate per-collection recheck right before each insert.
- Insert-only: `insert_many(ordered=True)`. No drop/delete/replace/update/
  upsert/merge/index-drop anywhere (enforced by a static test).
- Fail-closed import: missing `--execute` or a wrong `--confirm` aborts with a
  non-zero exit and writes nothing. No dry-run fallback.
- SHA-256 baseline gate: import is refused unless the dataset matches a
  separately approved `baseline.sha256`.
- No retry, no resume, no rollback. On failure the tool reports which
  collections were written/partial/unwritten, queries actual counts when
  possible, flags "POSSIBLE PARTIAL IMPORT — manual review required", and stops.
- Credential redaction applied to all output.

## Baseline (separate approval required)

`import_tool/baseline.sha256` is NOT created automatically and is intentionally
absent until you approve it. Until it exists, `integrity` and `import` refuse to
proceed. Creating it is a separate, explicitly-approved step.

## Scope

Everything lives under `mongodb-dev-seed/import_tool/` and
`tests/test_import_tool.py`. The tool makes no changes to the generator, dataset,
team repositories, Terraform, AWS, CI/CD, or the ECS deployment runbook, and it
creates no importer that bypasses these guards.
