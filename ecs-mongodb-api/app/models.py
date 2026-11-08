"""Pydantic response models — the stable JSON contract.

Field allowlists live here as tuples and are the single source of truth used by
serialization.project(). Auth/PII fields are intentionally absent and are also
blocked centrally by serialization.FORBIDDEN_FIELDS.
"""

from __future__ import annotations

from typing import Any, List

from pydantic import BaseModel

# ---- Field allowlists (no email/password/auth0/auth_provider/profile_picture) ----
SCHOOL_FIELDS = ("id", "school_name", "district_id", "status", "created_at", "updated_at")
USER_FIELDS = ("id", "first_name", "last_name", "role", "status", "school_id", "school", "created_at")
CLASS_FIELDS = ("id", "title", "section", "semester", "class_code", "status",
                "teacher", "students", "created_at")
ASSIGNMENT_FIELDS = ("id", "title", "description", "type", "category", "format",
                     "semester", "assigned_class", "settings", "passing_grade", "created_at")

# Reduced embedded shapes for class teacher/students (no email/auth0).
CLASS_TEACHER_FIELDS = ("id", "first_name", "last_name")
CLASS_STUDENT_FIELDS = ("id", "first_name", "last_name", "status")


class Pagination(BaseModel):
    limit: int
    offset: int
    count: int
    total: int


class Meta(BaseModel):
    database: str
    collection: str


class ListResponse(BaseModel):
    data: List[dict[str, Any]]
    pagination: Pagination
    meta: Meta


class HealthResponse(BaseModel):
    status: str


class ReadyResponse(BaseModel):
    status: str
    database: str
