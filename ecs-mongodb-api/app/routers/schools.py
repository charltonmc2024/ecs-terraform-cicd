from __future__ import annotations

from fastapi import APIRouter, Depends, Query

from ..deps import get_database
from ..models import ListResponse, SCHOOL_FIELDS
from ..security import require_api_key
from ._common import list_resource

router = APIRouter()


@router.get("/schools", response_model=ListResponse, tags=["schools"],
            dependencies=[Depends(require_api_key)])
async def list_schools(db=Depends(get_database),
                       limit: int = Query(default=20, ge=1, le=100),
                       offset: int = Query(default=0, ge=0)) -> dict:
    return list_resource(db, "schools", SCHOOL_FIELDS, limit=limit, offset=offset)
