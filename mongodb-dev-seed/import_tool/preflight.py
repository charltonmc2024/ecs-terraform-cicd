"""Read-only preflight: host/TLS (via connection), collection allowlist, empty check.

Uses count_documents({}) == 0 for the exact empty check (requirement 1). Rejects
any collection in either target DB that is not in the allowlist (requirement 2).
Performs NO writes.
"""

from __future__ import annotations

from . import config
from .report import ReportError


def run_preflight(client):
    """Return (ok, results). results: list of (scope, verdict, detail)."""
    results = []
    ok = True

    for db_name in config.ALLOWED_DBS:
        db = client[db_name]
        expected = set(config.EXPECTED_COLLECTIONS[db_name])
        try:
            existing = set(db.list_collection_names())
        except Exception as exc:
            raise ReportError(f"could not list collections for {db_name}: {type(exc).__name__}")

        unexpected = existing - expected
        if unexpected:
            ok = False
            results.append((f"{db_name}", "FAIL",
                            f"unexpected collection(s) present: {sorted(unexpected)}"))
        # Empty check: every target collection must be absent or count 0.
        for coll in config.EXPECTED_COLLECTIONS[db_name]:
            if coll not in existing:
                results.append((f"{db_name}.{coll}", "PASS", "absent (will be created on insert)"))
                continue
            n = db[coll].count_documents({})     # exact count (requirement 1)
            if n == 0:
                results.append((f"{db_name}.{coll}", "PASS", "empty (count 0)"))
            else:
                ok = False
                results.append((f"{db_name}.{coll}", "FAIL", f"NOT empty (count {n})"))
    return ok, results


def assert_collection_empty(client, db_name, coll):
    """Immediate pre-insert recheck for one collection; raise if not empty."""
    n = client[db_name][coll].count_documents({})
    if n != 0:
        raise ReportError(f"{db_name}.{coll} is not empty (count {n}); aborting before insert")
