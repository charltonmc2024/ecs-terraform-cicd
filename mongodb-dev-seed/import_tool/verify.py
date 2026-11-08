"""Post-import verification (read-only): counts vs MANIFEST + cross-references."""

from __future__ import annotations

from . import config
from .manifest import load_manifest
from .report import ReportError


def run_verify(client):
    """Return (ok, results). Read-only; queries counts and resolves references."""
    manifest = load_manifest()
    results = []
    ok = True

    # 1) Counts match MANIFEST.
    for db, colls in manifest.items():
        for coll, meta in colls.items():
            n = client[db][coll].count_documents({})
            if n == meta["count"]:
                results.append((f"{db}.{coll}", "PASS", f"count {n}"))
            else:
                ok = False
                results.append((f"{db}.{coll}", "FAIL", f"count {n} != {meta['count']}"))

    # 2) Cross-reference spot checks (ids only; read-only).
    try:
        ok = _check_refs(client, results) and ok
    except Exception as exc:
        ok = False
        results.append(("cross-refs", "FAIL", f"{type(exc).__name__}"))
    return ok, results


def _ids(client, db, coll):
    return {str(d["_id"]) for d in client[db][coll].find({}, {"_id": 1})}


def _check_refs(client, results):
    ts, as_ = config.TEACHER_STUDENT_DB, config.ADMIN_STAFF_DB
    district_ids = _ids(client, as_, "district_collection")
    as_school_ids = _ids(client, as_, "school_collection")
    ts_school_ids = _ids(client, ts, "school_collection")
    user_ids = _ids(client, ts, "user_collection")
    gq_ids = _ids(client, as_, "global_questionbank")

    ok = True
    # schools identical across both DBs
    if as_school_ids == ts_school_ids and as_school_ids:
        results.append(("schools-both-dbs", "PASS", f"{len(as_school_ids)} shared ids"))
    else:
        ok = False
        results.append(("schools-both-dbs", "FAIL", "school _id sets differ"))

    # school.district_id resolves
    bad = 0
    for s in client[as_]["school_collection"].find({}, {"district_id": 1}):
        if str(s.get("district_id")) not in district_ids:
            bad += 1
    results.append(("school->district", "PASS" if bad == 0 else "FAIL", f"{bad} dangling"))
    ok = ok and bad == 0

    # global_assignments.questions resolve to global_questionbank
    bad = 0
    for ga in client[as_]["global_assignments"].find({}, {"questions": 1}):
        for q in ga.get("questions", []):
            if str(q) not in gq_ids:
                bad += 1
    results.append(("global_assign->global_q", "PASS" if bad == 0 else "FAIL", f"{bad} dangling"))
    ok = ok and bad == 0

    # submissions reference existing assignments + students
    a_ids = _ids(client, ts, "assignments_collection")
    bad = 0
    for sub in client[ts]["submission_collection"].find({}, {"assignment_id": 1, "student_id": 1}):
        if str(sub.get("assignment_id")) not in a_ids:
            bad += 1
        if str(sub.get("student_id")) not in user_ids:
            bad += 1
    results.append(("submission->assign/student", "PASS" if bad == 0 else "FAIL", f"{bad} dangling"))
    ok = ok and bad == 0
    return ok
