"""FastAPI app factory: lifespan client, CORS allowlist, routers, safe errors.

Security posture:
  - /health is unauthenticated and does not touch MongoDB.
  - /ready and all data endpoints require the x-api-key header.
  - CORS is an allowlist and is explicitly NOT treated as authentication.
  - A logging filter redacts any mongodb URI and the API key so credentials
    never reach logs; error responses are generic.
  - All DB access is read-only.

Routing prefix (API_PREFIX):
  - Empty (default): routes are served at /ready, /schools, /users, /classes and
    /assignments, exactly as before.
  - Non-empty (for example /v1): those routes are served ONLY under the prefix, and
    trailing-slash redirects are disabled (a redirect behind CloudFront could point
    at the internal ALB host name).
  - /health is never prefixed (the ALB health check uses it).
  - An invalid prefix stops the process at startup. root_path is not used.
"""

from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from .config import get_settings, normalize_api_prefix
from .db import Database
from .routers import assignments, classes, health, schools, users

_URI_MARKERS = ("mongodb://", "mongodb+srv://")


class _RedactionFilter(logging.Filter):
    """Scrub connection URIs and the API key from every log record."""

    def filter(self, record: logging.LogRecord) -> bool:
        try:
            msg = record.getMessage()
        except Exception:
            return True
        settings = get_settings()
        redacted = msg
        if settings.api_key:
            redacted = redacted.replace(settings.api_key, "***REDACTED***")
        for marker in _URI_MARKERS:
            idx = redacted.find(marker)
            if idx != -1:
                redacted = redacted[:idx] + "***REDACTED_URI***"
        if redacted != msg:
            record.msg = redacted
            record.args = ()
        return True


def _install_redaction():
    f = _RedactionFilter()
    for name in ("", "uvicorn", "uvicorn.error", "uvicorn.access"):
        logging.getLogger(name).addFilter(f)


@asynccontextmanager
async def lifespan(app: FastAPI):
    _install_redaction()
    settings = get_settings()
    app.state.db = None
    # Connect lazily; a missing URI should not crash import (tests override db).
    if settings.mongodb_uri:
        try:
            app.state.db = Database.connect(settings)
        except Exception:
            # Do not leak details; readiness will report not-ready.
            logging.getLogger(__name__).error("database connection could not be established")
            app.state.db = None
    try:
        yield
    finally:
        db = getattr(app.state, "db", None)
        if db is not None:
            db.close()


def _route_plan(prefix: str):
    """(router, mount prefix) pairs in registration order. /health is never prefixed."""
    return [
        (health.router, ""),
        (health.ready_router, prefix),
        (schools.router, prefix),
        (users.router, prefix),
        (classes.router, prefix),
        (assignments.router, prefix),
    ]


def planned_routes(prefix: str):
    """Every (METHOD, full path) the app will serve for this prefix, in order."""
    planned = []
    for router, mount in _route_plan(prefix):
        for route in router.routes:
            for method in sorted(route.methods or ()):
                planned.append((method, mount + route.path))
    return planned


def create_app() -> FastAPI:
    settings = get_settings()
    # Fail fast on a malformed API_PREFIX (ValueError); nothing is served.
    prefix = normalize_api_prefix(settings.api_prefix)
    # Redirects are disabled only when a prefix is configured (deployed behind a proxy).
    app = FastAPI(
        title="eruditiontx-mongodb-api",
        version="0.1.0",
        lifespan=lifespan,
        redirect_slashes=not prefix,
    )

    if settings.cors_allow_origins:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=settings.cors_allow_origins,   # explicit allowlist, never "*"
            allow_credentials=False,
            allow_methods=["GET"],
            allow_headers=["x-api-key", "content-type"],
        )

    @app.exception_handler(Exception)
    async def _generic_error(_request: Request, _exc: Exception):
        # Never echo exception detail (could contain internals).
        return JSONResponse(status_code=500,
                            content={"error": {"code": 500, "message": "internal error"}})

    planned = planned_routes(prefix)
    if len(planned) != len(set(planned)):
        raise RuntimeError("duplicate route registration")
    for router, mount in _route_plan(prefix):
        app.include_router(router, prefix=mount)
    return app


app = create_app()
