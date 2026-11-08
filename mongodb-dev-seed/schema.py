"""Verified schema constants from the Step 1/Step 2 read-only source investigation.

These mirror the actual enums, limits and unique-index rules confirmed in the two
FastAPI services. They are duplicated here (not imported) because the generator must
be fully offline and must NOT depend on either application repository.

Sources (for traceability only; not imported at runtime):
  admin_staff (mathmatterstx-services):
    app/validators/feature_enum.py                PlanEnum
    app/validators/question_bank/input_validations.py  question enums
    app/validators/question_request_root_validators.py validate_keywords (1-10, <=50)
    app/models/assignment.py                       global_assignments model + settings
    app/database/assignment_indexes.py             title/feature_key unique-live indexes
    app/database/question_indexes.py               questionId_unique_sparse, etc.
  teacher_student (eruditiontx-services-mvp):
    server/models/classes.py / users.py / account.py / assignment.py
    server/connection/database.py                  EXPLICIT_INDEXES
"""

from __future__ import annotations

# --- Target databases ---------------------------------------------------------
TEACHER_STUDENT_DB = "teacher_student_db"
ADMIN_STAFF_DB = "admin_staff_mongodb"

# --- District / plan ----------------------------------------------------------
PLAN_VALUES = ["free", "basic", "intermediate", "premium"]  # PlanEnum

# --- Question bank (admin_staff + teacher) ------------------------------------
# AssignmentType in question_bank input_validations.py (differs from the
# Teacher-Student assignment enum below).
QB_ASSIGNMENT_TYPES = ["STAAR", "SAT", "ACT", "TSI", "College Level", "Erudition"]
QUESTION_TYPES = [
    "Multiple-choice", "Checkbox", "Free-response", "Graph", "Drop-down-Menu",
    "Drag-and-Drop", "Embedded-Multiple-Choice", "Multi-Select", "Equation-Editor",
    "Inline-Choice", "Number-Line", "Hot Spot", "Fraction-Model", "Single-Stimulus",
    "Multi-Part-Question", "Grid-Question", "Graph-Multiple-Select",
]
QB_CATEGORY = ["1", "2", "3", "4", "5"]            # Category enum (string digits)
DIFFICULTY = ["Easy", "Average", "Advance"]         # DifficultyType enum
SUBJECT = ["English", "Math", "Science", "Social Studies"]
GRADE_LEVEL = list(range(3, 13))                    # 3..12 (BSON int)

# Low-constraint question type used for the synthetic rows: "Erudition" avoids the
# STAAR teksCode/releaseDate requirements and the SAT/TSI/ACT field stripping.
QB_SAFE_ASSIGNMENT_TYPE = "Erudition"
QB_SAFE_QUESTION_TYPE = "Multiple-choice"

# keywords: 1..10 unique strings, each <= 50 chars (validate_keywords)
KEYWORDS_MAX_COUNT = 10
KEYWORDS_MAX_LEN = 50

# --- Teacher-Student assignment enums -----------------------------------------
TS_ASSIGNMENT_TYPES = ["STAAR", "ACT", "TSI", "SAT", "custom-test"]
TS_SAFE_ASSIGNMENT_TYPE = "custom-test"             # avoids exam-specific rules
ASSIGNMENT_SEMESTERS = ["fall", "spring", "summer 1", "summer 2"]
ASSIGNMENT_CATEGORY = ["current", "archived", "requested", "trashed"]
ASSIGNMENT_FORMAT = ["standard", "special", "practice"]
ASSIGNMENT_TITLE_MAX = 100
ASSIGNMENT_DESC_MAX = 500
ASSIGNMENT_MAX_QUESTIONS = 100

# AssignmentSettings defaults (valid HH:MM:SS, allowed_attempts >= 1)
DEFAULT_SETTINGS = {
    "time_allowed": "01:00:00",
    "allowed_attempts": 1,
    "shuffle_questions": False,
    "shuffle_choices": False,
    "allow_calculator": False,
    "show_score_after_submit": False,
    "show_correct_answers_after_submit": False,
    "allow_feedback_after_submit": False,
}

# --- Agreed dataset quantities ------------------------------------------------
COUNTS = {
    "districts": 2,
    "schools": 4,
    "teachers": 4,
    "students": 12,
    "classes": 4,
    "assignments": 8,
    "submissions": 24,
    "teacher_questions": 8,
    "global_questions": 4,
    "global_assignments": 2,
}

# --- Unique-index rules the generated data must satisfy -----------------------
# collection -> list of unique key tuples (field names) that must not collide.
UNIQUE_KEYS = {
    (ADMIN_STAFF_DB, "school_collection"): [("school_name",), ("email",)],
    (ADMIN_STAFF_DB, "global_assignments"): [("title",)],  # partial: deleted=false
    (ADMIN_STAFF_DB, "global_questionbank"): [("questionId",)],  # sparse: nulls ok
    (TEACHER_STUDENT_DB, "user_collection"): [("email",)],
    (TEACHER_STUDENT_DB, "class_collection"): [("class_code",)],
    (TEACHER_STUDENT_DB, "submission_collection"): [("student_id", "assignment_id")],
    (TEACHER_STUDENT_DB, "teacher_questionbank"): [("questionId",)],  # sparse
}

# Synthetic Auth0 subject sentinel — clearly NOT a real Auth0 user.
AUTH0_SENTINEL_PREFIX = "auth0|SYNTHETIC-"
# All synthetic logins are unusable: password is always empty (Auth0 is the authority).
EMPTY_PASSWORD = ""
