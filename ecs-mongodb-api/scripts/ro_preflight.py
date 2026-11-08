#!/usr/bin/env python3
"""Read-only MongoDB Atlas connectivity preflight.

STRICTLY READ-ONLY. This script performs NO writes of any kind (no insert, update,
delete, replace, drop, createIndex, or any mutating command). It verifies:

  1. Connectivity          - admin.command("ping")
  2. Authenticated roles   - connectionStatus (read-only command): confirm ONLY
                             database-scoped `read` roles on the two expected DBs.
                             If roles cannot be determined, report UNVERIFIED and
                             stop (non-zero exit) rather than assuming success.
  3. Collection counts     - count_documents({}) for each of the 10 expected
                             collections, compared to the approved local manifest.
  4. Total                 - sum of counts equals 76.

Credential safety:
  - MONGODB_URI is read from the environment and NEVER printed or logged.
  - On any error, only the exception TYPE is shown; the message (which could echo
    the URI/host/user) is suppressed, and any mongodb URI substring is scrubbed.
  - Output is limited to: database names, collection names, counts, role names,
    and PASS/FAIL/UNVERIFIED statuses. No document contents.

Exit codes: 0 = all PASS; 1 = FAIL; 2 = UNVERIFIED; 3 = usage/setup error.

Expected counts come from the approved manifest at
  ../mongodb-dev-seed/output/MANIFEST.json
(relative to this repo), read-only. A fixed fallback mapping is used only if the
manifest is not present, and that case is reported.
"""

from __future__ import annotations

import json
import os
import sys

# ---- Expected (db -> collection -> count). Fixed, reviewed mapping as a fallback. ----
FIXED_EXPECTED = {
    "teacher_student_db": {
        "user_collection": 16,
        "class_collection": 4,
        "assignments_collection": 8,
        "submission_collection": 24,
        "teacher_questionbank": 8,
        "school_collection": 4,
    },
    "admin_staff_mongodb": {
        "district_collection": 2,
        "school_collection": 4,
        "global_questionbank": 4,
        "global_assignments": 2,
    },
}
EXPECTED_TOTAL = 76

# Roles we accept: built-in "read" scoped to exactly these two databases.
EXPECTED_READ_DBS = {"teacher_student_db", "admin_staff_mongodb"}
ALLOWED_ROLE_NAMES = {"read"}

MANIFEST_RELPATH = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", "..",
    "mongodb-dev-seed", "output", "MANIFEST.json",
)


def _scrub(text: str) -> str:
    """Remove any mongodb URI fragment from a string (defensive)."""
    out = text
    for marker in ("mongodb+srv://", "mongodb://"):
        i = out.find(marker)
        if i != -1:
            out = out[:i] + "<redacted-uri>"
    return out


def load_expected():
    """Return (expected_map, source_label). Uses the manifest if available."""
    path = os.path.normpath(MANIFEST_RELPATH)
    if os.path.exists(path):
        try:
            with open(path, encoding="utf-8") as fh:
                manifest = json.load(fh)
            expected = {
                db: {c: int(meta["count"]) for c, meta in colls.items()}
                for db, colls in manifest.items()
            }
            return expected, f"manifest ({path})"
        except Exception as exc:  # pragma: no cover - defensive
            print(f"WARN  could not parse manifest ({type(exc).__name__}); using fixed mapping")
    return FIXED_EXPECTED, "fixed reviewed mapping"


def get_uri_or_exit() -> str:
    uri = os.environ.get("MONGODB_URI", "")
    if not uri:
        print("SETUP FAIL: MONGODB_URI is not set in the environment.")
        sys.exit(3)
    return uri


def check_roles(client) -> str:
    """Return 'PASS', 'FAIL', or 'UNVERIFIED' for the read-only role expectation.

    Uses connectionStatus (a read-only command). Confirms the authenticated user
    holds ONLY db-scoped `read` roles on the two expected databases and no broader
    role. Never prints the username.
    """
    try:
        status = client.admin.command("connectionStatus", showPrivileges=False)
    except Exception as exc:
        print(f"ROLES UNVERIFIED: connectionStatus failed ({type(exc).__name__})")
        return "UNVERIFIED"

    authinfo = (status or {}).get("authInfo", {})
    roles = authinfo.get("authenticatedUserRoles")
    if roles is None:
        print("ROLES UNVERIFIED: authenticatedUserRoles not present in connectionStatus")
        return "UNVERIFIED"
    if not roles:
        # Authenticated but no roles reported -> cannot confirm read access.
        print("ROLES UNVERIFIED: no authenticated roles reported")
        return "UNVERIFIED"

    verdict = "PASS"
    for r in roles:
        role = r.get("role")
        db = r.get("db")
        if role in ALLOWED_ROLE_NAMES and db in EXPECTED_READ_DBS:
            print(f"ROLE OK   role={role} db={db}")
        else:
            # Any role outside the allowlist (e.g. readWrite, atlasAdmin, root,
            # a read on an unexpected db) is a FAIL for this read-only preflight.
            print(f"ROLE FAIL role={role} db={db} (outside read-only expectation)")
            verdict = "FAIL"

    covered = {r.get("db") for r in roles if r.get("role") in ALLOWED_ROLE_NAMES}
    missing = EXPECTED_READ_DBS - covered
    if missing:
        for db in sorted(missing):
            print(f"ROLE FAIL missing read role on db={db}")
        verdict = "FAIL"
    return verdict


def check_counts(client, expected) -> str:
    verdict = "PASS"
    total = 0
    for db in sorted(expected):
        for coll in sorted(expected[db]):
            exp = expected[db][coll]
            try:
                n = client[db][coll].count_documents({})
            except Exception as exc:
                print(f"COUNT FAIL {db}.{coll}: error ({type(exc).__name__})")
                verdict = "FAIL"
                continue
            total += n
            if n == exp:
                print(f"COUNT OK   {db}.{coll}: {n}")
            else:
                print(f"COUNT FAIL {db}.{coll}: {n} (expected {exp})")
                verdict = "FAIL"
    if total == EXPECTED_TOTAL:
        print(f"TOTAL OK   {total} documents")
    else:
        print(f"TOTAL FAIL {total} (expected {EXPECTED_TOTAL})")
        verdict = "FAIL"
    return verdict


def main() -> int:
    expected, source = load_expected()
    print(f"expected counts source: {source}")

    uri = get_uri_or_exit()

    try:
        from pymongo import MongoClient
    except Exception as exc:
        print(f"SETUP FAIL: pymongo unavailable ({type(exc).__name__})")
        return 3

    timeout_ms = int(os.environ.get("MONGO_SERVER_SELECTION_TIMEOUT_MS", "5000"))
    client = None
    try:
        client = MongoClient(
            uri,
            tls=True,
            tlsAllowInvalidCertificates=False,
            serverSelectionTimeoutMS=timeout_ms,
            appname="eruditiontx-mongodb-api-ro-preflight",
        )
        # 1) Connectivity
        try:
            client.admin.command("ping")
            print("PING OK")
        except Exception as exc:
            print(f"PING FAIL: {type(exc).__name__}")
            return 1

        # 2) Roles (read-only commands)
        roles_verdict = check_roles(client)
        if roles_verdict == "UNVERIFIED":
            print("RESULT: UNVERIFIED (role verification inconclusive) - stopping")
            return 2

        # 3) + 4) Counts and total
        counts_verdict = check_counts(client, expected)

        overall = "PASS" if (roles_verdict == "PASS" and counts_verdict == "PASS") else "FAIL"
        print(f"RESULT: {overall}")
        return 0 if overall == "PASS" else 1
    except Exception as exc:
        # Suppress the exception message (could echo URI/host/user); show type only.
        print(_scrub(f"UNEXPECTED ERROR: {type(exc).__name__}"))
        return 1
    finally:
        if client is not None:
            client.close()


if __name__ == "__main__":
    sys.exit(main())
