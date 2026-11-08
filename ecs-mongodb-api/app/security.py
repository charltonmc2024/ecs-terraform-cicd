"""API-key authentication boundary. CORS is NOT authentication.

A valid `x-api-key` header must match the configured API_KEY. Missing/invalid ->
generic 401 (no detail that could aid guessing). /health is exempt; /ready is
protected (per Step 10B decision).
"""

from __future__ import annotations

from fastapi import Header, HTTPException, status

from .config import get_settings


async def require_api_key(x_api_key: str | None = Header(default=None)) -> None:
    settings = get_settings()
    expected = settings.api_key
    # Fail closed: if no API_KEY is configured, deny protected routes.
    if not expected or not x_api_key or not _constant_time_eq(x_api_key, expected):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="unauthorized",
            headers={"WWW-Authenticate": "ApiKey"},
        )


def _constant_time_eq(a: str, b: str) -> bool:
    import hmac
    return hmac.compare_digest(a.encode("utf-8"), b.encode("utf-8"))
