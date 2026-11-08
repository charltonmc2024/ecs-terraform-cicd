"""Bounded pagination and the stable response envelope."""

from __future__ import annotations

DEFAULT_LIMIT = 20
MAX_LIMIT = 100


def clamp_limit(limit: int | None) -> int:
    if limit is None:
        return DEFAULT_LIMIT
    if limit < 1:
        return 1
    if limit > MAX_LIMIT:
        return MAX_LIMIT
    return limit


def clamp_offset(offset: int | None) -> int:
    if offset is None or offset < 0:
        return 0
    return offset


def envelope(data, *, limit, offset, total, database, collection) -> dict:
    return {
        "data": data,
        "pagination": {
            "limit": limit,
            "offset": offset,
            "count": len(data),
            "total": total,
        },
        "meta": {"database": database, "collection": collection},
    }
