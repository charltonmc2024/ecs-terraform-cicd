"""Offline validation tests for the synthetic dataset. Pure stdlib (unittest).

No MongoDB connection is made anywhere in this suite. It validates the in-memory
dataset and the written Extended JSON files against the verified schema rules.

Run:  python3 -m unittest discover -s tests -v   (from the mongodb-dev-seed dir)
"""

from __future__ import annotations

import json
import os
import sys
import unittest

# Make the parent package importable when run from tests/.
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import schema as S                      # noqa: E402
from objectid import oid, is_valid_oid  # noqa: E402
from ejson import Oid, Date             # noqa: E402
import generate as G                    # noqa: E402

OUTPUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "output")


class DatasetTestBase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data = G.build_all()

    def coll(self, db, name):
        return self.data[(db, name)]


class TestCounts(DatasetTestBase):
    def test_counts_match_agreed_quantities(self):
        c = S.COUNTS
        users = self.coll(S.TEACHER_STUDENT_DB, "user_collection")
        teachers = [u for u in users if u["role"] == "teacher"]
        students = [u for u in users if u["role"] == "student"]
        self.assertEqual(len(teachers), c["teachers"])
        self.assertEqual(len(students), c["students"])
        self.assertEqual(len(self.coll(S.ADMIN_STAFF_DB, "district_collection")), c["districts"])
        self.assertEqual(len(self.coll(S.ADMIN_STAFF_DB, "school_collection")), c["schools"])
        self.assertEqual(len(self.coll(S.TEACHER_STUDENT_DB, "class_collection")), c["classes"])
        self.assertEqual(len(self.coll(S.TEACHER_STUDENT_DB, "assignments_collection")), c["assignments"])
        self.assertEqual(len(self.coll(S.TEACHER_STUDENT_DB, "submission_collection")), c["submissions"])
        self.assertEqual(len(self.coll(S.TEACHER_STUDENT_DB, "teacher_questionbank")), c["teacher_questions"])
        self.assertEqual(len(self.coll(S.ADMIN_STAFF_DB, "global_questionbank")), c["global_questions"])
        self.assertEqual(len(self.coll(S.ADMIN_STAFF_DB, "global_assignments")), c["global_assignments"])


class TestObjectIds(DatasetTestBase):
    def test_all_ids_valid_and_unique_per_collection(self):
        for (db, name), docs in self.data.items():
            ids = [d["_id"].value for d in docs]
            for v in ids:
                self.assertTrue(is_valid_oid(v), f"{db}.{name}: invalid oid {v}")
            self.assertEqual(len(ids), len(set(ids)), f"{db}.{name}: duplicate _id")

    def test_ids_are_oid_markers(self):
        for (db, name), docs in self.data.items():
            for d in docs:
                self.assertIsInstance(d["_id"], Oid)


class TestRequiredFieldsAndTypes(DatasetTestBase):
    def test_users(self):
        for u in self.coll(S.TEACHER_STUDENT_DB, "user_collection"):
            for f in ("first_name", "last_name", "role", "email"):
                self.assertIsInstance(u[f], str)
                self.assertTrue(u[f])
            self.assertIn(u["role"], ("teacher", "student"))
            self.assertEqual(u["password"], S.EMPTY_PASSWORD)   # no usable credential
            self.assertTrue(u["auth0_user_id"].startswith(S.AUTH0_SENTINEL_PREFIX))
            self.assertIsInstance(u["school_id"], Oid)

    def test_districts(self):
        for d in self.coll(S.ADMIN_STAFF_DB, "district_collection"):
            self.assertIn(d["feature_plan"], S.PLAN_VALUES)
            self.assertGreaterEqual(len(d["district_name"]), 3)
            self.assertIs(d["deleted"], False)

    def test_classes(self):
        for c in self.coll(S.TEACHER_STUDENT_DB, "class_collection"):
            self.assertTrue(c["title"])
            self.assertLessEqual(len(c["title"]), 100)
            self.assertIsInstance(c["class_code"], str)
            self.assertIs(c["deleted"], False)
            self.assertIsInstance(c["teacher"]["_id"], Oid)
            self.assertTrue(1 <= len(c["students"]) <= 100)

    def test_assignments(self):
        for a in self.coll(S.TEACHER_STUDENT_DB, "assignments_collection"):
            self.assertIn(a["type"], S.TS_ASSIGNMENT_TYPES)
            self.assertIn(a["semester"], S.ASSIGNMENT_SEMESTERS)
            self.assertIn(a["category"], S.ASSIGNMENT_CATEGORY)
            self.assertIn(a["format"], S.ASSIGNMENT_FORMAT)
            self.assertTrue(0 < len(a["questions"]) <= S.ASSIGNMENT_MAX_QUESTIONS)
            self.assertLessEqual(len(a["title"]), S.ASSIGNMENT_TITLE_MAX)
            self.assertLessEqual(len(a["description"]), S.ASSIGNMENT_DESC_MAX)
            self.assertTrue(any(ch.isalnum() for ch in a["title"]))
            s = a["settings"]
            self.assertGreaterEqual(s["allowed_attempts"], 1)
            self.assertRegex(s["time_allowed"], r"^\d{2}:\d{2}:\d{2}$")
            self.assertNotEqual(s["time_allowed"], "00:00:00")

    def test_submissions(self):
        for sub in self.coll(S.TEACHER_STUDENT_DB, "submission_collection"):
            self.assertIsInstance(sub["assignment_id"], Oid)
            self.assertIsInstance(sub["student_id"], Oid)
            self.assertTrue(len(sub["answers"]) >= 1)
            for ans in sub["answers"]:
                for f in ("question_id", "user_answer", "is_correct"):
                    self.assertIn(f, ans)
                self.assertIsInstance(ans["is_correct"], bool)

    def test_questions(self):
        for coll in ("teacher_questionbank",):
            for q in self.coll(S.TEACHER_STUDENT_DB, coll):
                self._check_question(q)
        for q in self.coll(S.ADMIN_STAFF_DB, "global_questionbank"):
            self._check_question(q)

    def _check_question(self, q):
        self.assertIn(q["assignmentType"], S.QB_ASSIGNMENT_TYPES)
        self.assertIn(q["questionType"], S.QUESTION_TYPES)
        self.assertIn(q["questionSubject"], S.SUBJECT)
        self.assertIn(q["difficulty"], S.DIFFICULTY)
        self.assertIn(q["category"], S.QB_CATEGORY)
        self.assertIn(q["gradeLevel"], S.GRADE_LEVEL)
        self.assertIsInstance(q["points"], int)
        self.assertNotIsInstance(q["points"], bool)
        self.assertTrue(1 <= len(q["keywords"]) <= S.KEYWORDS_MAX_COUNT)
        self.assertEqual(len(q["keywords"]), len(set(k.casefold() for k in q["keywords"])))
        for k in q["keywords"]:
            self.assertTrue(0 < len(k) <= S.KEYWORDS_MAX_LEN)
        self.assertIsNone(q["questionId"])      # sparse-unique: null is fine
        self.assertEqual(q["questionImages"], [])   # no MinIO references

    def test_global_assignments(self):
        titles = []
        for ga in self.coll(S.ADMIN_STAFF_DB, "global_assignments"):
            self.assertIs(ga["deleted"], False)            # required explicit
            self.assertNotIn("feature_key", ga)            # omitted
            self.assertTrue(ga["title"])
            titles.append(ga["title"])
            self.assertTrue(0 < len(ga["questions"]) <= 100)
        self.assertEqual(len(titles), len(set(titles)))     # unique titles


class TestUniqueConstraints(DatasetTestBase):
    def test_unique_keys(self):
        for (db, coll), keysets in S.UNIQUE_KEYS.items():
            docs = self.data.get((db, coll), [])
            for keys in keysets:
                seen = set()
                for d in docs:
                    parts = []
                    missing = False
                    for k in keys:
                        v = d.get(k)
                        if v is None:
                            missing = True
                            break
                        parts.append(v.value if isinstance(v, Oid) else v)
                    if missing:      # sparse / partial: nulls not indexed
                        continue
                    tup = tuple(parts)
                    self.assertNotIn(tup, seen, f"{db}.{coll}: dup {keys}={tup}")
                    seen.add(tup)


class TestCrossDatabaseReferences(DatasetTestBase):
    def test_schools_same_id_both_dbs(self):
        ts = {s["_id"].value for s in self.coll(S.TEACHER_STUDENT_DB, "school_collection")}
        admin = {s["_id"].value for s in self.coll(S.ADMIN_STAFF_DB, "school_collection")}
        self.assertEqual(ts, admin)

    def test_school_district_refs_resolve(self):
        district_ids = {d["_id"].value for d in self.coll(S.ADMIN_STAFF_DB, "district_collection")}
        for s in self.coll(S.ADMIN_STAFF_DB, "school_collection"):
            self.assertIn(s["district_id"].value, district_ids)

    def test_user_school_refs_resolve(self):
        school_ids = {s["_id"].value for s in self.coll(S.ADMIN_STAFF_DB, "school_collection")}
        for u in self.coll(S.TEACHER_STUDENT_DB, "user_collection"):
            self.assertIn(u["school_id"].value, school_ids)

    def test_class_embeds_real_users(self):
        user_ids = {u["_id"].value for u in self.coll(S.TEACHER_STUDENT_DB, "user_collection")}
        for c in self.coll(S.TEACHER_STUDENT_DB, "class_collection"):
            self.assertIn(c["teacher"]["_id"].value, user_ids)
            for st in c["students"]:
                self.assertIn(st["_id"].value, user_ids)

    def test_assignment_class_refs_resolve(self):
        class_ids = {c["_id"].value for c in self.coll(S.TEACHER_STUDENT_DB, "class_collection")}
        for a in self.coll(S.TEACHER_STUDENT_DB, "assignments_collection"):
            for cid in a["assigned_class"]:
                self.assertIn(cid.value, class_ids)

    def test_submission_refs_resolve(self):
        a_ids = {a["_id"].value for a in self.coll(S.TEACHER_STUDENT_DB, "assignments_collection")}
        u_ids = {u["_id"].value for u in self.coll(S.TEACHER_STUDENT_DB, "user_collection")}
        for sub in self.coll(S.TEACHER_STUDENT_DB, "submission_collection"):
            self.assertIn(sub["assignment_id"].value, a_ids)
            self.assertIn(sub["student_id"].value, u_ids)

    def test_global_assignment_question_refs_resolve(self):
        gq_ids = {q["_id"].value for q in self.coll(S.ADMIN_STAFF_DB, "global_questionbank")}
        for ga in self.coll(S.ADMIN_STAFF_DB, "global_assignments"):
            for qid in ga["questions"]:
                val = qid.value if isinstance(qid, Oid) else qid
                self.assertIn(val, gq_ids)


class TestDeterminismAndIdempotency(DatasetTestBase):
    def test_build_is_deterministic(self):
        a = G.build_all()
        b = G.build_all()
        self.assertEqual(_flatten_ids(a), _flatten_ids(b))

    def test_ids_are_stable_known_values(self):
        # Idempotent record identifiers: a known logical key always maps to the
        # same id, so re-imports upsert rather than duplicate.
        self.assertEqual(oid("district", "district-1"), oid("district", "district-1"))
        self.assertTrue(oid("district", "district-1").startswith("0001"))
        self.assertTrue(oid("global_assignment", "global-assignment-1").startswith("000b"))


class TestNoBrokenExternalRefs(DatasetTestBase):
    def test_no_image_object_keys(self):
        for c in self.coll(S.TEACHER_STUDENT_DB, "class_collection"):
            self.assertIsNone(c["class_photo"])
        for u in self.coll(S.TEACHER_STUDENT_DB, "user_collection"):
            self.assertIsNone(u["profile_picture"])
        for q in self.coll(S.ADMIN_STAFF_DB, "global_questionbank"):
            self.assertEqual(q["questionImages"], [])


class TestWrittenFilesAreExtendedJSON(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        G.write_output()

    def test_manifest_and_oid_date_wrappers(self):
        with open(os.path.join(OUTPUT_DIR, "MANIFEST.json"), encoding="utf-8") as fh:
            manifest = json.load(fh)
        self.assertIn(S.TEACHER_STUDENT_DB, manifest)
        self.assertIn(S.ADMIN_STAFF_DB, manifest)
        # Spot-check one file parses and uses Extended JSON wrappers.
        path = os.path.join(OUTPUT_DIR, f"{S.ADMIN_STAFF_DB}.district_collection.json")
        with open(path, encoding="utf-8") as fh:
            docs = json.load(fh)
        self.assertEqual(len(docs), S.COUNTS["districts"])
        self.assertIn("$oid", docs[0]["_id"])
        self.assertIn("$date", docs[0]["created_at"])
        self.assertEqual(len(docs[0]["_id"]["$oid"]), 24)


class TestStep4BCorrections(DatasetTestBase):
    """Regression tests for the three Step 4B compatibility corrections."""

    def _is_hex24(self, v):
        return isinstance(v, str) and len(v) == 24 and all(c in "0123456789abcdef" for c in v)

    def test_no_invalid_email_domain(self):
        # Correction 1: emails must not use the reserved .invalid TLD that
        # pydantic EmailStr rejects; use a resolvable-looking example domain.
        def emails_in(doc):
            out = []
            for k, v in doc.items():
                if isinstance(v, str) and "@" in v and k.endswith(("email",)):
                    out.append(v)
            return out
        checked = 0
        for (db, name), docs in self.data.items():
            for d in docs:
                for e in emails_in(d):
                    checked += 1
                    self.assertFalse(e.endswith(".invalid"),
                                     f"{db}.{name}: email uses .invalid: {e}")
                    self.assertTrue(e.endswith("@example.com"),
                                    f"{db}.{name}: unexpected email domain: {e}")
                # embedded teacher/students in classes
                if name == "class_collection":
                    self.assertFalse(d["teacher"]["email"].endswith(".invalid"))
                    for st in d["students"]:
                        self.assertFalse(st["email"].endswith(".invalid"))
        self.assertGreater(checked, 0)

    def test_assignment_question_refs_are_hex_strings(self):
        # Correction 2: assignment/global_assignment questions must be 24-hex
        # id STRINGS, never Oid markers (which serialise to $oid objects the
        # Pydantic model rejects for the questions list).
        for coll in ("assignments_collection",):
            for a in self.coll(S.TEACHER_STUDENT_DB, coll):
                self.assertTrue(len(a["questions"]) >= 1)
                for q in a["questions"]:
                    self.assertNotIsInstance(q, Oid)
                    self.assertTrue(self._is_hex24(q), f"question ref not hex24: {q!r}")
        for ga in self.coll(S.ADMIN_STAFF_DB, "global_assignments"):
            for q in ga["questions"]:
                self.assertNotIsInstance(q, Oid)
                self.assertTrue(self._is_hex24(q), f"global question ref not hex24: {q!r}")

    def test_teacher_questions_have_solutions(self):
        # Step 4C: teacher_questionbank must carry a non-empty solutions string
        # (required by the Teacher-Student question create model). global_questionbank
        # is intentionally left without it (optional there).
        for q in self.coll(S.TEACHER_STUDENT_DB, "teacher_questionbank"):
            self.assertIn("solutions", q)
            self.assertIsInstance(q["solutions"], str)
            self.assertTrue(q["solutions"].strip(), "solutions must be non-empty")
        for q in self.coll(S.ADMIN_STAFF_DB, "global_questionbank"):
            # left unchanged: no solutions key added
            self.assertNotIn("solutions", q)

    def test_question_created_by_is_null(self):
        # Correction 3: no dangling admin account reference.
        for q in self.coll(S.TEACHER_STUDENT_DB, "teacher_questionbank"):
            self.assertIsNone(q["createdBy"])
        for q in self.coll(S.ADMIN_STAFF_DB, "global_questionbank"):
            self.assertIsNone(q["createdBy"])


def _flatten_ids(dataset):
    out = {}
    for (db, name), docs in dataset.items():
        out[f"{db}.{name}"] = [d["_id"].value for d in docs]
    return out


if __name__ == "__main__":
    unittest.main(verbosity=2)
