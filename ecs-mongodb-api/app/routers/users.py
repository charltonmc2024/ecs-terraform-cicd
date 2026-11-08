from __future__ import annotations

from typing import Optional

from fastapi import APIRouter, Depends, Query

from ..deps import get_database
from ..models import ListResponse, USER_FIELDS
from ..security import require_api_key
from ._common import list_resource

router = APIRouter()


@router.get("/users", response_model=ListResponse, tags=["users"],
            dependencies=[Depends(require_api_key)])
async def list_users(db=Depends(get_database),
                     role: Optional[str] = Query(default=None, pattern="^(teacher|student)$"),
                     limit: int = Query(default=20, ge=1, le=100),
                     offset: int = Query(default=0, ge=0)) -> dict:
    flt = {"role": role} if role else {}
    return list_resource(db, "users", USER_FIELDS, limit=limit, offset=offset,
                         extra_filter=flt)
