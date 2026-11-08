"""Dependency provider for the database handle.

In production the lifespan stores a real Database on app.state.db. In tests the
dependency is overridden with a fake, so no pymongo client and no network are
ever used offline.
"""

from __future__ import annotations

from fastapi import Request


def get_database(request: Request):
    db = getattr(request.app.state, "db", None)
    if db is None:
        # Should not happen in normal operation; generic failure.
        from fastapi import HTTPException, status
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                            detail="database unavailable")
    return db
