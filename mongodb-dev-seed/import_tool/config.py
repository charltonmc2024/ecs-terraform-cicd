"""Frozen, non-secret constants for the import tool.

Nothing in this file is a credential. The password is NEVER stored here; it is
read at run time from the ATLAS_PASSWORD environment variable by the connecting
modes only. The username and hostname below are fixed, non-secret identifiers.
"""

from __future__ import annotations

import os

# --- Fixed connection identity (NON-SECRET) ----------------------------------
ATLAS_USER = "eruditiontx_ecs_dev"                 # fixed; not a secret
APPROVED_HOST = "ecscluster.xoiozdv.mongodb.net"   # the ONLY allowed target host
PASSWORD_ENV = "ATLAS_PASSWORD"                    # secret source (value never logged)

# --- Allowlists ---------------------------------------------------------------
TEACHER_STUDENT_DB = "teacher_student_db"
ADMIN_STAFF_DB = "admin_staff_mongodb"
ALLOWED_DBS = (TEACHER_STUDENT_DB, ADMIN_STAFF_DB)

# The exact 10 target collections per database (nothing else may exist or import).
EXPECTED_COLLECTIONS = {
    TEACHER_STUDENT_DB: (
        "user_collection",
        "class_collection",
        "assignments_collection",
        "submission_collection",
        "teacher_questionbank",
        "school_collection",
    ),
    ADMIN_STAFF_DB: (
        "district_collection",
        "school_collection",
        "global_questionbank",
        "global_assignments",
    ),
}

EXPECTED_TOTAL_DOCS = 76

# Insert order (admin_staff first, then teacher_student) preserving references.
IMPORT_ORDER = [
    (ADMIN_STAFF_DB, "district_collection"),
    (ADMIN_STAFF_DB, "school_collection"),
    (ADMIN_STAFF_DB, "global_questionbank"),
    (ADMIN_STAFF_DB, "global_assignments"),
    (TEACHER_STUDENT_DB, "school_collection"),
    (TEACHER_STUDENT_DB, "user_collection"),
    (TEACHER_STUDENT_DB, "teacher_questionbank"),
    (TEACHER_STUDENT_DB, "class_collection"),
    (TEACHER_STUDENT_DB, "assignments_collection"),
    (TEACHER_STUDENT_DB, "submission_collection"),
]

# Hard denylist: if any of these appear in the resolved target host, abort.
DENY_HOST_SUBSTRINGS = (
    "localhost", "127.0.0.1", "::1",
    "mathmattersqa.com", "eruditiontx.com",   # team/self-hosted domains
    "10.", "172.", "192.168.",                # private ranges
)

# --- Paths --------------------------------------------------------------------
_HERE = os.path.dirname(os.path.abspath(__file__))
SEED_DIR = os.path.dirname(_HERE)
OUTPUT_DIR = os.path.realpath(os.path.join(SEED_DIR, "output"))
MANIFEST_PATH = os.path.join(OUTPUT_DIR, "MANIFEST.json")
BASELINE_PATH = os.path.join(_HERE, "baseline.sha256")

# Required exact confirmation phrase for a real import (double opt-in).
CONFIRM_PHRASE = "IMPORT teacher_student_db,admin_staff_mongodb"
