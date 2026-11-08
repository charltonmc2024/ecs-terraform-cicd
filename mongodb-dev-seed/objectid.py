"""Deterministic, valid MongoDB ObjectId strings — no pymongo/bson required.

A MongoDB ObjectId is exactly 24 hexadecimal characters (12 bytes). For a
synthetic, repeatable dataset we do not need time-ordered ids; we only need:

  * valid: exactly 24 lowercase hex chars,
  * deterministic: the same logical entity always maps to the same id,
  * collision-free within this dataset.

We derive each id from a stable namespace + key via SHA-256 and take the first
24 hex chars. This is pure stdlib, so the generator has zero third-party
dependencies and can never touch a database.

Readable id-block prefixes (first 4 hex) make cross-references easy to eyeball:
  district 0001  school 0002  teacher 0003  student 0004  class 0005
  assignment 0006  submission 0007  account 0008  teacher_q 0009
  global_q 000a  global_assignment 000b
"""

from __future__ import annotations

import hashlib

# Fixed project salt so ids are stable across runs but specific to this dataset.
_SALT = "eruditiontx-mongodb-dev-seed/v1"

PREFIXES = {
    "district": "0001",
    "school": "0002",
    "teacher": "0003",
    "student": "0004",
    "class": "0005",
    "assignment": "0006",
    "submission": "0007",
    "account": "0008",
    "teacher_question": "0009",
    "global_question": "000a",
    "global_assignment": "000b",
}


def oid(kind: str, key: str) -> str:
    """Return a deterministic 24-hex-char ObjectId string for (kind, key).

    The 4-char kind prefix is followed by 20 hex chars derived from a SHA-256 of
    the salt, kind and key. Same inputs -> same id, every run.
    """
    if kind not in PREFIXES:
        raise KeyError(f"unknown id kind: {kind!r}")
    prefix = PREFIXES[kind]
    digest = hashlib.sha256(f"{_SALT}|{kind}|{key}".encode("utf-8")).hexdigest()
    value = prefix + digest[: 24 - len(prefix)]
    assert len(value) == 24 and all(c in "0123456789abcdef" for c in value), value
    return value


def is_valid_oid(value: str) -> bool:
    """True when value is exactly 24 lowercase/upper hex characters."""
    if not isinstance(value, str) or len(value) != 24:
        return False
    try:
        int(value, 16)
    except ValueError:
        return False
    return True
