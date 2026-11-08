from datetime import datetime, timezone

import pytest

from app.serialization import project, to_jsonable, FORBIDDEN_FIELDS


class _OID:
    def __init__(self, v): self._v = v
    def __str__(self): return self._v
# Make type name look like ObjectId for the serializer's duck check.
_OID.__name__ = "ObjectId"


def test_objectid_and_datetime():
    assert to_jsonable(_OID("abc")) == "abc"
    dt = datetime(2026, 1, 1, tzinfo=timezone.utc)
    assert to_jsonable(dt) == "2026-01-01T00:00:00.000Z"


def test_project_maps_id_and_filters():
    doc = {"_id": _OID("0003"), "first_name": "T", "email": "x@example.com",
           "password": "", "auth0_user_id": "auth0|x", "role": "teacher"}
    out = project(doc, ("id", "first_name", "role", "status"))
    assert out["id"] == "0003"
    assert out["first_name"] == "T"
    assert out["role"] == "teacher"
    # Forbidden/omitted fields never appear:
    for k in ("email", "password", "auth0_user_id", "auth_provider"):
        assert k not in out


def test_allowlist_rejects_forbidden_field():
    with pytest.raises(ValueError):
        project({"_id": _OID("1")}, ("id", "email"))


def test_forbidden_set_contents():
    assert {"email", "password", "auth0_user_id", "auth_provider"} <= FORBIDDEN_FIELDS
