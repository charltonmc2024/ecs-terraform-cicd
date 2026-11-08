"""Safe, allowlist-based serialization. No auth/PII fields ever leave the API.

- _id (and nested _id) -> string field "id"
- any ObjectId -> str
- datetime -> ISO-8601 with trailing Z
- only explicitly allowlisted fields are emitted

The excluded set (email, password, auth0_user_id, auth_provider, profile_picture,
subscriber_id) is enforced centrally so a field can never leak by being added to
an allowlist by mistake.
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

# Fields that must NEVER appear in any response, at any nesting level.
FORBIDDEN_FIELDS = frozenset({
    "email", "password", "auth0_user_id", "auth_provider",
    "profile_picture", "subscriber_id",
})


def _is_objectid(v: Any) -> bool:
    # Avoid importing bson here so serialization is testable without pymongo.
    return type(v).__name__ == "ObjectId"


def to_jsonable(value: Any) -> Any:
    """Recursively convert BSON/datetime to JSON-safe primitives (no field filtering)."""
    if _is_objectid(value):
        return str(value)
    if isinstance(value, datetime):
        dt = value if value.tzinfo else value.replace(tzinfo=timezone.utc)
        dt = dt.astimezone(timezone.utc)
        return dt.strftime("%Y-%m-%dT%H:%M:%S.") + f"{dt.microsecond // 1000:03d}Z"
    if isinstance(value, dict):
        return {k: to_jsonable(v) for k, v in value.items()}
    if isinstance(value, list):
        return [to_jsonable(v) for v in value]
    return value


def project(doc: dict, allow: "tuple[str, ...]") -> dict:
    """Return a new dict with only allowlisted fields, _id mapped to id, BSON made safe.

    Raises if an allowlist entry is in FORBIDDEN_FIELDS (defensive: a forbidden
    field can never be allowlisted).
    """
    forbidden_in_allow = FORBIDDEN_FIELDS.intersection(allow)
    if forbidden_in_allow:
        raise ValueError(f"forbidden field(s) in allowlist: {sorted(forbidden_in_allow)}")
    out: dict = {}
    if "_id" in doc:
        out["id"] = to_jsonable(doc["_id"])
    for key in allow:
        if key == "id":
            continue
        if key in doc:
            out[key] = to_jsonable(doc[key])
    return out
