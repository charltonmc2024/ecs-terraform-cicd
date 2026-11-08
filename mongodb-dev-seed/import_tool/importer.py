"""Insert-only import. Fail-closed. No retry/resume. No destructive operations.

This module contains ONLY insert_many plus read-only count/empty checks. It never
calls drop, delete, replace, update, upsert, merge, or any index-drop. A static
test asserts those API names are absent from this source.

Safety flow per collection, in IMPORT_ORDER:
  1. recheck count_documents({}) == 0 immediately before inserting (TOCTOU guard)
  2. insert_many(docs, ordered=True)  -- stop on first error
On any failure: report which collections were fully/partly/not written, query
actual counts when possible, flag POSSIBLE PARTIAL IMPORT, and STOP. Never retry,
never resume, never delete/roll back.
"""

from __future__ import annotations

from . import config
from .manifest import load_manifest, resolve_in_output
from .preflight import assert_collection_empty
from .report import ReportError, redact


def _require_json_util():
    try:
        from bson import json_util
        return json_util
    except Exception:
        raise ReportError("bson.json_util is required to load documents for import.")


def _load_docs(json_util, filename):
    path = resolve_in_output(filename)
    with open(path, encoding="utf-8") as fh:
        docs = json_util.loads(fh.read())
    if not isinstance(docs, list):
        raise ReportError(f"{filename}: top-level is not a JSON array")
    return docs


def run_import(client, execute: bool, confirm: str):
    """Perform the guarded insert-only import.

    FAIL CLOSED: if execute is not True OR confirm != the exact phrase, raise and
    write nothing. There is no silent dry-run fallback.
    """
    if execute is not True or confirm != config.CONFIRM_PHRASE:
        raise ReportError(
            "import refused: both --execute and the exact --confirm phrase are required. "
            "No dry-run fallback."
        )

    json_util = _require_json_util()
    manifest = load_manifest()

    status = {}  # (db, coll) -> "written" | "partial" | "unwritten"
    for db, coll in config.IMPORT_ORDER:
        status[(db, coll)] = "unwritten"

    for db, coll in config.IMPORT_ORDER:
        meta = manifest[db][coll]
        docs = _load_docs(json_util, meta["file"])
        # Immediate pre-insert empty recheck (requirement 2).
        assert_collection_empty(client, db, coll)
        try:
            if docs:
                client[db][coll].insert_many(docs, ordered=True)
            status[(db, coll)] = "written"
        except Exception as exc:
            status[(db, coll)] = "partial"
            _report_partial(client, status, db, coll, exc)
            # NO retry, NO resume, NO rollback.
            raise ReportError(
                f"import STOPPED at {db}.{coll}: {type(exc).__name__}. "
                "POSSIBLE PARTIAL IMPORT - manual review required. No automatic "
                "retry, resume, or rollback was performed."
            )
    return status


def _report_partial(client, status, failed_db, failed_coll, exc):
    print(redact(f"IMPORT FAILURE at {failed_db}.{failed_coll}: {type(exc).__name__}"))
    print("POSSIBLE PARTIAL IMPORT - manual review required.")
    print("Per-collection status (and queried counts where possible):")
    for (db, coll), state in status.items():
        count_str = "?"
        try:
            count_str = str(client[db][coll].count_documents({}))
        except Exception:
            count_str = "unavailable"
        print(redact(f"  {db}.{coll}: {state}  (actual count: {count_str})"))
