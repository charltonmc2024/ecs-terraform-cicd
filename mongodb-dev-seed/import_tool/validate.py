"""Offline Extended JSON validation. Requires bson.json_util; fails closed if absent.

No network. Validates each file: parses as a JSON array via bson.json_util,
document count equals MANIFEST, every _id is a 24-hex ObjectId, and no duplicate
_id within a collection.
"""

from __future__ import annotations

from . import config
from .manifest import load_manifest, entries
from .report import ReportError


def _require_json_util():
    try:
        from bson import json_util, ObjectId  # noqa: F401
        return json_util, ObjectId
    except Exception:
        # Fail closed (requirement 2): do NOT fall back to a weaker parser.
        raise ReportError(
            "bson.json_util is required for Extended JSON validation but is not "
            "available in this interpreter. Run with an environment that has pymongo/bson."
        )


def validate_all():
    """Return (ok, results). results: list of (db, coll, verdict, detail)."""
    json_util, ObjectId = _require_json_util()
    manifest = load_manifest()
    results = []
    total = 0
    ok_all = True
    for db, coll, path, expected in entries(manifest):
        verdict, detail, n = _validate_file(json_util, ObjectId, path, expected)
        total += n
        if verdict != "PASS":
            ok_all = False
        results.append((db, coll, verdict, detail))
    if total != config.EXPECTED_TOTAL_DOCS:
        ok_all = False
        results.append(("-", "TOTAL", "FAIL",
                        f"total docs {total} != {config.EXPECTED_TOTAL_DOCS}"))
    else:
        results.append(("-", "TOTAL", "PASS", f"{total} documents"))
    return ok_all, results


def _validate_file(json_util, ObjectId, path, expected):
    try:
        with open(path, encoding="utf-8") as fh:
            docs = json_util.loads(fh.read())
    except FileNotFoundError:
        return "FAIL", "file not found", 0
    except Exception as exc:
        return "FAIL", f"not valid Extended JSON: {type(exc).__name__}", 0
    if not isinstance(docs, list):
        return "FAIL", "top-level is not a JSON array", 0
    if len(docs) != expected:
        return "FAIL", f"count {len(docs)} != manifest {expected}", len(docs)
    seen = set()
    for i, d in enumerate(docs):
        if not isinstance(d, dict) or "_id" not in d:
            return "FAIL", f"doc[{i}] missing _id", len(docs)
        _id = d["_id"]
        oid = str(_id)
        if isinstance(_id, ObjectId):
            oid = str(_id)
        if len(oid) != 24 or any(c not in "0123456789abcdef" for c in oid.lower()):
            return "FAIL", f"doc[{i}] _id not a 24-hex ObjectId", len(docs)
        if oid in seen:
            return "FAIL", f"duplicate _id {oid[:6]}...", len(docs)
        seen.add(oid)
    return "PASS", f"{len(docs)} docs valid", len(docs)
