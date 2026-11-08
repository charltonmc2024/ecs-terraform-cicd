"""Health (unauthenticated, DB-independent) and readiness (API-key protected).

Two routers so they can be mounted separately:
  - `router`        : GET /health. Always mounted WITHOUT the API prefix, so the ALB
                      health check path stays /health.
  - `ready_router`  : GET /ready. Mounted under the configured API prefix, like the
                      data endpoints, and protected by the API key.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status

from ..deps import get_database
from ..models import HealthResponse, ReadyResponse
from ..security import require_api_key

router = APIRouter()
ready_router = APIRouter()


@router.get("/health", response_model=HealthResponse, tags=["health"])
async def health() -> HealthResponse:
    # No DB access: liveness only. Always 200 while the process is up.
    return HealthResponse(status="ok")


@ready_router.get(
    "/ready",
    response_model=ReadyResponse,
    tags=["health"],
    dependencies=[Depends(require_api_key)],   # protected per Step 10B
)
async def ready(db=Depends(get_database)) -> ReadyResponse:
    try:
        db.ping()
    except Exception:
        # Generic message; no driver/URI detail.
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail="not ready"
        )
    return ReadyResponse(status="ready", database="reachable")
