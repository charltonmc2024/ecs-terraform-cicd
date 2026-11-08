from __future__ import annotations

from fastapi import APIRouter, Depends, Query

from ..deps import get_database
from ..models import ListResponse, ASSIGNMENT_FIELDS
from ..security import require_api_key
from ._common import list_resource

router = APIRouter()


@router.get("/assignments", response_model=ListResponse, tags=["assignments"],
            dependencies=[Depends(require_api_key)])
async def list_assignments(db=Depends(get_database),
                           limit: int = Query(default=20, ge=1, le=100),
                           offset: int = Query(default=0, ge=0)) -> dict:
    # questions intentionally omitted from ASSIGNMENT_FIELDS (Step 10B decision).
    return list_resource(db, "assignments", ASSIGNMENT_FIELDS, limit=limit, offset=offset)
