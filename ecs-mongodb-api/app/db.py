"""Read-only MongoDB access with a fixed (db, collection) allowlist.

The PyMongo client is created lazily inside the FastAPI lifespan and reused. This
module calls ONLY read operations (find, count_documents, command('ping')). There
is no write method anywhere; tests/test_no_writes.py enforces that statically.

pymongo is imported lazily so unit tests can inject a fake database without the
driver and without any network.
"""

from __future__ import annotations

from typing import Any

from .config import Settings

# Logical resource -> (which db setting, collection name). Endpoints reference
# these keys only; user input never chooses a namespace.
RESOURCES = {
    "schools": ("admin_staff_db", "school_collection"),
    "users": ("teacher_student_db", "user_collection"),
    "classes": ("teacher_student_db", "class_collection"),
    "assignments": ("teacher_student_db", "assignments_collection"),
}


class Database:
    """Thin read-only wrapper around a pymongo client (or an injected fake)."""

    def __init__(self, client: Any, settings: Settings):
        self._client = client
        self._settings = settings

    @classmethod
    def connect(cls, settings: Settings) -> "Database":
        if not settings.mongodb_uri:
            raise RuntimeError("MONGODB_URI is not set")
        from pymongo import MongoClient  # lazy import; never during offline tests

        client = MongoClient(
            settings.mongodb_uri,                 # already contains the read-only user
            tls=True,
            tlsAllowInvalidCertificates=False,
            serverSelectionTimeoutMS=settings.server_selection_timeout_ms,
            appname="eruditiontx-mongodb-api-ro",
        )
        return cls(client, settings)

    def _db_name(self, which: str) -> str:
        return getattr(self._settings, which)

    def collection(self, resource: str):
        which, coll = RESOURCES[resource]
        return self._client[self._db_name(which)][coll]

    def names(self, resource: str):
        which, coll = RESOURCES[resource]
        return self._db_name(which), coll

    def ping(self) -> bool:
        # Read-only admin command; raises on failure.
        self._client.admin.command("ping")
        return True

    def close(self) -> None:
        close = getattr(self._client, "close", None)
        if callable(close):
            close()
