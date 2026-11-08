"""Offline synthetic dataset generator for the two LMS databases.

OFFLINE ONLY. This module imports no database driver, opens no socket, and has no
write-to-MongoDB capability. It builds in-memory documents and writes MongoDB
Extended JSON v2 files under ./output/. A separate (NOT included) controlled import
step would later load them; this tool never imports.

Entities and quantities (schema.COUNTS):
  2 districts, 4 schools, 4 teachers, 12 students, 4 classes, 8 assignments,
  ~24 submissions, 8 teacher questions, 4 global questions, 2 global assignments.

Cross-database references use the same deterministic ObjectIds on both sides:
  * schools are seeded in BOTH databases with identical _id,
  * class embeds the teacher/student user _ids from teacher_student_db,
  * submissions reference assignment_id + student_id,
  * assignment.assigned_class references class _ids,
  * global assignments reference global_questionbank _ids.
"""

from __future__ import annotations

import os

from objectid import oid
from ejson import Oid, Date, FIXED_NOW, dumps
import schema as S

OUTPUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "output")

NOW = Date(FIXED_NOW)


def _auth0_sentinel(role: str, n: int) -> str:
    # Clearly synthetic, non-resolvable Auth0 subject. NOT a real credential.
    return f"{S.AUTH0_SENTINEL_PREFIX}{role}-{n:018d}"


# --------------------------------------------------------------------------- #
# Builders. Each returns a list of dicts (one collection).                    #
# --------------------------------------------------------------------------- #

def build_districts():
    docs = []
    for i in range(1, S.COUNTS["districts"] + 1):
        key = f"district-{i}"
        docs.append({
            "_id": Oid(oid("district", key)),
            "district_name": f"Synthetic District {i}",
            "district_address": f"{100 + i} Example Ave, Austin, TX 7870{i}",
            "district_logo": None,
            "contact_first_name": f"DistrictContact{i}",
            "contact_middle_name": None,
            "contact_last_name": "Synthetic",
            "contact_email": f"district{i}@example.com",
            "contact_phone": "5120000000",
            "feature_plan": "free",            # PlanEnum value
            "created_at": NOW,
            "created_by": None,
            "updated_by": None,
            "updated_at": None,
            "deleted_by": None,
            "deleted_at": None,
            "deleted": False,
        })
    return docs


def _school_doc(i, district_oid):
    key = f"school-{i}"
    return {
        "_id": Oid(oid("school", key)),
        "school_name": f"Synthetic School {i}",      # unique
        "email": f"school{i}@example.com",        # unique
        "district_id": district_oid,
        "status": "active",
        "created_at": NOW,
        "updated_at": None,
    }


def build_schools(districts):
    # 4 schools, 2 per district.
    docs = []
    for i in range(1, S.COUNTS["schools"] + 1):
        district = districts[(i - 1) // 2]
        docs.append(_school_doc(i, district["_id"]))
    return docs


def build_teachers(schools):
    docs = []
    for i in range(1, S.COUNTS["teachers"] + 1):
        key = f"teacher-{i}"
        school = schools[i - 1]  # one teacher per school
        docs.append({
            "_id": Oid(oid("teacher", key)),
            "school_id": school["_id"],
            "school": school["school_name"][:40],
            "first_name": f"Teacher{i:04d}",
            "last_name": "Synthetic",
            "role": "teacher",
            "status": "active",
            "email": f"teacher{i:04d}@example.com",   # unique
            "password": S.EMPTY_PASSWORD,                  # Auth0 is the authority
            "auth0_user_id": _auth0_sentinel("teacher", i),
            "auth_provider": "local",
            "profile_picture": None,
            "created_at": NOW,
            "updated_at": None,
        })
    return docs


def build_students(schools):
    docs = []
    for i in range(1, S.COUNTS["students"] + 1):
        key = f"student-{i}"
        # 12 students spread across 4 schools (3 each).
        school = schools[(i - 1) // 3]
        docs.append({
            "_id": Oid(oid("student", key)),
            "school_id": school["_id"],
            "school": school["school_name"][:40],
            "first_name": f"Student{i:04d}",
            "last_name": "Synthetic",
            "role": "student",
            "status": "active",
            "email": f"student{i:04d}@example.com",   # unique
            "password": S.EMPTY_PASSWORD,
            "auth0_user_id": _auth0_sentinel("student", i),
            "auth_provider": "local",
            "profile_picture": None,
            "created_at": NOW,
            "updated_at": None,
        })
    return docs


def _embedded_teacher(t):
    return {
        "_id": t["_id"],
        "subscriber_id": None,
        "auth0_user_id": t["auth0_user_id"],
        "first_name": t["first_name"],
        "last_name": t["last_name"],
        "email": t["email"],
    }


def _embedded_student(s):
    return {
        "_id": s["_id"],
        "subscriber_id": None,
        "auth0_user_id": s["auth0_user_id"],
        "first_name": s["first_name"],
        "middle_name": None,
        "last_name": s["last_name"],
        "email": s["email"],
        "status": "active",
        "is_requesting_to_leave": False,
    }


def build_classes(teachers, students):
    docs = []
    for i in range(1, S.COUNTS["classes"] + 1):
        key = f"class-{i}"
        teacher = teachers[i - 1]                   # one class per teacher
        # 3 students per class, aligned to the same school grouping.
        members = students[(i - 1) * 3:(i - 1) * 3 + 3]
        docs.append({
            "_id": Oid(oid("class", key)),
            "title": f"Synthetic Class {i}",
            "description": "",
            "section": f"SEC-{i:02d}",
            "semester": "Fall",
            "class_code": f"SYN{i:03d}",            # unique class_code_1
            "schedules": [],
            "status": "VISIBLE",
            "teacher": _embedded_teacher(teacher),
            "students": [_embedded_student(s) for s in members],
            "class_photo": None,                     # no S3/MinIO ref
            "deleted": False,
            "deleted_at": None,
            "dedupe_key": f"{teacher['_id'].value}|synthetic class {i}|sec-{i:02d}",
            "created_at": NOW,
            "updated_at": NOW,
        })
    return docs


def build_assignments(classes):
    docs = []
    for i in range(1, S.COUNTS["assignments"] + 1):
        key = f"assignment-{i}"
        cls = classes[(i - 1) // 2]                 # 2 assignments per class
        docs.append({
            "_id": Oid(oid("assignment", key)),
            "semester": "spring",
            "type": S.TS_SAFE_ASSIGNMENT_TYPE,       # custom-test (low constraint)
            "category": "current",
            "format": "standard",
            "title": f"Synthetic Assignment {i}",    # <=100, alphanumeric
            "description": f"Synthetic assignment number {i} for development.",
            # Question refs in an assignment are id STRINGS (model accepts str|{id}), not $oid.
            "questions": [oid("teacher_question", f"tq-{((i - 1) % S.COUNTS['teacher_questions']) + 1}")],
            "assigned_class": [cls["_id"]],
            "date_open": None,
            "date_close": None,
            "settings": dict(S.DEFAULT_SETTINGS),
            "deleted": False,
            "created_at": NOW,
            "created_by": None,
            "dedupe_key": f"synthetic-assignment-{i}",
            "updated_at": None,
            "passing_grade": 70,
        })
    return docs


def build_submissions(assignments, classes, students):
    """~24 submissions: one per (student, assignment) for each student in the
    assignment's class. 4 classes x 2 assignments x 3 students = 24."""
    docs = []
    # Map class _id -> its student list.
    class_students = {}
    for cls in classes:
        class_students[cls["_id"].value] = [st["_id"] for st in cls["students"]]
    n = 0
    for a in assignments:
        for class_oid in a["assigned_class"]:
            for student_oid in class_students[class_oid.value]:
                n += 1
                key = f"sub-{a['_id'].value}-{student_oid.value}"
                docs.append({
                    "_id": Oid(oid("submission", key)),
                    "assignment_id": a["_id"],
                    "student_id": student_oid,       # unique (student_id, assignment_id)
                    "total_score": 0,
                    "remarks": "PENDING",
                    "answers": [
                        {
                            "question_id": a["questions"][0],  # already a hex id string
                            "user_answer": "A",
                            "is_correct": False,
                        }
                    ],
                    "submitted_answers": None,
                    "submitted_at": NOW,
                })
    return docs


def _keywords(i):
    # 1..10 unique strings, each <= 50 chars.
    return [f"synthetic", f"dev", f"q{i}"][: S.KEYWORDS_MAX_COUNT]


def _question_doc(kind, i):
    key = f"{'tq' if kind == 'teacher_question' else 'gq'}-{i}"
    doc = {
        "_id": Oid(oid(kind, key)),
        "assignmentType": S.QB_SAFE_ASSIGNMENT_TYPE,   # Erudition
        "questionType": S.QB_SAFE_QUESTION_TYPE,        # Multiple-choice
        "question": f"Synthetic question {i}: what is {i} + {i}?",
        "questionSubject": "Math",
        "questionDetails": None,
        "questionId": None,                              # sparse unique -> null ok
        "questionImages": [],                            # no MinIO refs
        "questionGraphs": [],
        "choices": [
            {"id": 1, "text": str(i + i), "graph": ""},
            {"id": 2, "text": str(i + i + 1), "graph": ""},
        ],
        "correctAnswer": {"answers": [str(i + i)], "answerDetails": None, "graph": ""},
        "difficulty": "Easy",
        "gradeLevel": S.GRADE_LEVEL[(i - 1) % len(S.GRADE_LEVEL)],
        "keywords": _keywords(i),
        "points": 1,
        "category": "1",
        "createdDate": NOW,
        "createdBy": None,  # startup owns admin/staff accounts; no dangling ref
        "deleted": False,
    }
    # The Teacher-Student question create model requires a non-empty `solutions`
    # string (eruditiontx QuestionModelCreate: `solutions: str`). The Admin-Staff
    # global model makes it Optional, so global_questionbank is left unchanged.
    if kind == "teacher_question":
        doc["solutions"] = f"Synthetic worked solution for question {i}: {i} + {i} = {i + i}."
    return doc


def build_teacher_questions(teachers):
    docs = []
    for i in range(1, S.COUNTS["teacher_questions"] + 1):
        docs.append(_question_doc("teacher_question", i))
    return docs


def build_global_questions():
    docs = []
    for i in range(1, S.COUNTS["global_questions"] + 1):
        docs.append(_question_doc("global_question", i))
    return docs


def build_global_assignments(global_questions):
    docs = []
    for i in range(1, S.COUNTS["global_assignments"] + 1):
        key = f"global-assignment-{i}"
        gq = global_questions[(i - 1) % len(global_questions)]
        docs.append({
            "_id": Oid(oid("global_assignment", key)),
            "semester": "spring",
            "type": "custom-test",                    # low-constraint
            "category": "current",
            "format": "standard",
            "title": f"Synthetic Global Assignment {i:04d}",  # unique among live
            "description": f"Synthetic global bank assignment {i}.",
            "questions": [gq["_id"].value],  # id STRING, not $oid (model accepts str|{id})
            "assigned_class": [],
            "date_open": None,
            "date_close": None,
            "settings": dict(S.DEFAULT_SETTINGS),
            "deleted": False,                          # REQUIRED explicit for unique index
            "created_at": NOW,
            "created_by": None,
            "updated_at": None,
            "updated_by": None,
            "deleted_at": None,
            "deleted_by": None,
            "passing_grade": 70,
            "copy_of": None,
            "version": 1,
            # feature_key omitted (not a tiered practice global)
            "instructions": None,
            "rubric": None,
        })
    return docs


def build_all():
    """Build every collection and return {(db, collection): [docs]}."""
    districts = build_districts()
    schools = build_schools(districts)
    teachers = build_teachers(schools)
    students = build_students(schools)
    classes = build_classes(teachers, students)
    assignments = build_assignments(classes)
    submissions = build_submissions(assignments, classes, students)
    teacher_questions = build_teacher_questions(teachers)
    # createdBy is null on questions: app startup owns admin/staff accounts,
    # so we never point at an account id that isn't in the dataset.
    global_questions = build_global_questions()
    global_assignments = build_global_assignments(global_questions)

    return {
        (S.TEACHER_STUDENT_DB, "user_collection"): teachers + students,
        (S.TEACHER_STUDENT_DB, "class_collection"): classes,
        (S.TEACHER_STUDENT_DB, "assignments_collection"): assignments,
        (S.TEACHER_STUDENT_DB, "submission_collection"): submissions,
        (S.TEACHER_STUDENT_DB, "teacher_questionbank"): teacher_questions,
        (S.TEACHER_STUDENT_DB, "school_collection"): schools,       # cross-DB (same ids)
        (S.ADMIN_STAFF_DB, "district_collection"): districts,
        (S.ADMIN_STAFF_DB, "school_collection"): schools,           # same _id as TS side
        (S.ADMIN_STAFF_DB, "global_questionbank"): global_questions,
        (S.ADMIN_STAFF_DB, "global_assignments"): global_assignments,
    }


def write_output(dataset=None):
    dataset = dataset or build_all()
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    manifest = {}
    written = []
    for (db, coll), docs in dataset.items():
        fname = f"{db}.{coll}.json"
        path = os.path.join(OUTPUT_DIR, fname)
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(dumps(docs))
            fh.write("\n")
        manifest.setdefault(db, {})[coll] = {"file": fname, "count": len(docs)}
        written.append((fname, len(docs)))
    with open(os.path.join(OUTPUT_DIR, "MANIFEST.json"), "w", encoding="utf-8") as fh:
        import json
        fh.write(json.dumps(manifest, indent=2))
        fh.write("\n")
    return written


if __name__ == "__main__":
    for fname, count in write_output():
        print(f"wrote output/{fname}  ({count} docs)")
    print("Format: MongoDB Extended JSON v2 (canonical). No database connection used.")
