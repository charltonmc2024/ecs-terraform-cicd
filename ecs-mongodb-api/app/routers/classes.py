from __future__ import annotations

from fastapi import APIRouter, Depends, Query

from ..deps import get_database
from ..models import (ListResponse, CLASS_FIELDS, CLASS_TEACHER_FIELDS,
                      CLASS_STUDENT_FIELDS)
from ..security import require_api_key
from ..serialization import project
from ._common import list_resource

router = APIRouter()


def _reduce_embedded(doc, item):
    """Replace embedded teacher/students with reduced, auth/PII-free shapes."""
    teacher = doc.get("teacher")
    if isinstance(teacher, dict):
        item["teacher"] = project(teacher, CLASS_TEACHER_FIELDS)
    students = doc.get("students")
    if isinstance(students, list):
        item["students"] = [project(s, CLASS_STUDENT_FIELDS)
                            for s in students if isinstance(s, dict)]
    return item


@router.get("/classes", response_model=ListResponse, tags=["classes"],
            dependencies=[Depends(require_api_key)])
async def list_classes(db=Depends(get_database),
                       limit: int = Query(default=20, ge=1, le=100),
                       offset: int = Query(default=0, ge=0)) -> dict:
    return list_resource(db, "classes", CLASS_FIELDS, limit=limit, offset=offset,
                         transform=_reduce_embedded)
