"""Offline test fixtures: a fake in-memory DB. No pymongo, no network."""

from __future__ import annotations

import os
import sys

import pytest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# Deterministic, offline test environment. This runs when pytest imports conftest, which
# is before any test module imports app.main (its module-level create_app() reads the
# environment). It overrides whatever is exported in the developer's shell, so no real
# prefix, database URI, or API key can reach or break the tests. The changes live only
# in this pytest process (os.environ of this process); the parent shell is untouched.
for _name in ("API_PREFIX", "MONGODB_URI"):
    os.environ.pop(_name, None)                      # absent: default routes, no DB client
os.environ["API_KEY"] = "test-key-not-a-secret"      # fake; forced, never setdefault
os.environ["CORS_ALLOW_ORIGINS"] = "http://localhost:3000"
os.environ["PORT"] = "8080"
os.environ["MONGO_SERVER_SELECTION_TIMEOUT_MS"] = "5000"
os.environ["TEACHER_STUDENT_DB"] = "teacher_student_db"
os.environ["ADMIN_STAFF_DB"] = "admin_staff_mongodb"

from app.db import RESOURCES  # noqa: E402


class FakeCursor:
    def __init__(self, docs):
        self._docs = list(docs)

    def sort(self, key, direction=1):
        self._docs.sort(key=lambda d: str(d.get("_id")), reverse=(direction == -1))
        return self

    def skip(self, n):
        self._docs = self._docs[n:]
        return self

    def limit(self, n):
        self._docs = self._docs[:n]
        return self

    def __iter__(self):
        return iter(self._docs)


class FakeCollection:
    def __init__(self, docs):
        self._docs = list(docs)

    def count_documents(self, flt):
        return len(self._match(flt))

    def find(self, flt=None):
        return FakeCursor(self._match(flt or {}))

    def _match(self, flt):
        if not flt:
            return list(self._docs)
        return [d for d in self._docs if all(d.get(k) == v for k, v in flt.items())]


class FakeDatabase:
    """Implements the Database interface used by the routers."""

    def __init__(self, collections, ping_ok=True):
        # collections: {resource_key: [docs]}
        self._collections = {k: FakeCollection(v) for k, v in collections.items()}
        self._ping_ok = ping_ok

    def collection(self, resource):
        return self._collections[resource]

    def names(self, resource):
        which, coll = RESOURCES[resource]
        return ("admin_staff_mongodb" if which == "admin_staff_db" else "teacher_student_db"), coll

    def ping(self):
        if not self._ping_ok:
            raise RuntimeError("ping failed")
        return True

    def close(self):
        pass


def _oid(hexstr):
    # A stand-in ObjectId-like object: serialization checks type name "ObjectId".
    class ObjectId:
        def __init__(self, v): self._v = v
        def __str__(self): return self._v
    return ObjectId(hexstr)


@pytest.fixture
def sample_data():
    from datetime import datetime, timezone
    now = datetime(2026, 1, 1, tzinfo=timezone.utc)
    schools = [
        {"_id": _oid("0002f04aae58fceb8e2c1584"), "school_name": "Synthetic School 1",
         "email": "school1@example.com", "district_id": _oid("00017cce82fdbea3dcd230f0"),
         "status": "active", "created_at": now, "updated_at": None},
    ]
    users = [
        {"_id": _oid("0003077ace3e18ed1c535c3b"), "school_id": _oid("0002f04aae58fceb8e2c1584"),
         "school": "Synthetic School 1", "first_name": "Teacher0001", "last_name": "Synthetic",
         "role": "teacher", "status": "active", "email": "teacher0001@example.com",
         "password": "", "auth0_user_id": "auth0|SYNTHETIC-teacher-1", "auth_provider": "local",
         "profile_picture": None, "created_at": now, "updated_at": None},
        {"_id": _oid("00049ff1e61612309bed1fc3"), "school_id": _oid("0002f04aae58fceb8e2c1584"),
         "school": "Synthetic School 1", "first_name": "Student0001", "last_name": "Synthetic",
         "role": "student", "status": "active", "email": "student0001@example.com",
         "password": "", "auth0_user_id": "auth0|SYNTHETIC-student-1", "auth_provider": "local",
         "profile_picture": None, "created_at": now, "updated_at": None},
    ]
    classes = [
        {"_id": _oid("00057ed8eea4f8a7c35edee3"), "title": "Synthetic Class 1",
         "description": "", "section": "SEC-01", "semester": "Fall", "class_code": "SYN001",
         "schedules": [], "status": "VISIBLE",
         "teacher": {"_id": _oid("0003077ace3e18ed1c535c3b"), "subscriber_id": None,
                     "auth0_user_id": "auth0|SYNTHETIC-teacher-1", "first_name": "Teacher0001",
                     "last_name": "Synthetic", "email": "teacher0001@example.com"},
         "students": [{"_id": _oid("00049ff1e61612309bed1fc3"), "subscriber_id": None,
                       "auth0_user_id": "auth0|SYNTHETIC-student-1", "first_name": "Student0001",
                       "middle_name": None, "last_name": "Synthetic",
                       "email": "student0001@example.com", "status": "active",
                       "is_requesting_to_leave": False}],
         "class_photo": None, "deleted": False, "created_at": now, "updated_at": now},
    ]
    assignments = [
        {"_id": _oid("00067dd802d19838ae6452c0"), "semester": "spring", "type": "custom-test",
         "category": "current", "format": "standard", "title": "Synthetic Assignment 1",
         "description": "Synthetic assignment number 1 for development.",
         "questions": ["0009fe5601e2db75cc4e444b"],
         "assigned_class": [_oid("00057ed8eea4f8a7c35edee3")], "date_open": None,
         "date_close": None, "settings": {"time_allowed": "01:00:00", "allowed_attempts": 1},
         "deleted": False, "created_at": now, "passing_grade": 70},
    ]
    return {"schools": schools, "users": users, "classes": classes, "assignments": assignments}


@pytest.fixture
def client(sample_data):
    from fastapi.testclient import TestClient
    from app.main import create_app
    from app.deps import get_database

    app = create_app()
    fake = FakeDatabase(sample_data)
    app.dependency_overrides[get_database] = lambda: fake
    with TestClient(app) as c:
        yield c
