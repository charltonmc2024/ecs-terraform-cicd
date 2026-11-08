"""MongoDB Extended JSON v2 helpers — stdlib only, no bson/pymongo.

Output format: MongoDB Extended JSON v2 (canonical), the format `mongoimport`
consumes directly. Two wrapper types are produced:

  ObjectId  -> {"$oid": "<24-hex>"}
  datetime  -> {"$date": "<ISO-8601 Z>"}

Using thin marker classes keeps the generator readable (fields hold Oid/Date
objects) while the custom json encoder renders the Extended JSON at write time.
There is no code path here that opens a socket or a database connection.
"""

from __future__ import annotations

import json
from datetime import datetime, timezone


class Oid:
    """Marker for an ObjectId; serialises to {"$oid": value}."""

    __slots__ = ("value",)

    def __init__(self, value: str):
        self.value = value

    def __eq__(self, other):
        return isinstance(other, Oid) and other.value == self.value

    def __hash__(self):
        return hash(("Oid", self.value))

    def __repr__(self):
        return f"Oid({self.value!r})"


class Date:
    """Marker for a BSON date; serialises to {"$date": iso8601Z}."""

    __slots__ = ("dt",)

    def __init__(self, dt: datetime):
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        self.dt = dt.astimezone(timezone.utc)

    def iso(self) -> str:
        # Millisecond precision with trailing Z, matching Extended JSON v2.
        return self.dt.strftime("%Y-%m-%dT%H:%M:%S.") + f"{self.dt.microsecond // 1000:03d}Z"

    def __repr__(self):
        return f"Date({self.iso()})"


class ExtendedJSONEncoder(json.JSONEncoder):
    def default(self, o):
        if isinstance(o, Oid):
            return {"$oid": o.value}
        if isinstance(o, Date):
            return {"$date": o.iso()}
        return super().default(o)


def dumps(docs) -> str:
    """Canonical Extended JSON v2 array, pretty-printed, deterministic key order."""
    return json.dumps(docs, cls=ExtendedJSONEncoder, indent=2, sort_keys=False)


# A fixed, deterministic base timestamp for all generated datetimes (UTC).
# No wall-clock reads, so output is byte-identical every run.
FIXED_NOW = datetime(2026, 1, 1, 0, 0, 0, tzinfo=timezone.utc)
