"""Shared list-endpoint logic: bounded pagination, deterministic sort, projection."""

from __future__ import annotations

from ..pagination import clamp_limit, clamp_offset, envelope
from ..serialization import project


def list_resource(db, resource, allow, *, limit, offset, extra_filter=None, transform=None):
    limit = clamp_limit(limit)
    offset = clamp_offset(offset)
    coll = db.collection(resource)
    database, collection = db.names(resource)
    flt = extra_filter or {}
    total = coll.count_documents(flt)
    cursor = coll.find(flt).sort("_id", 1).skip(offset).limit(limit)
    data = []
    for doc in cursor:
        item = project(doc, allow)
        if transform is not None:
            item = transform(doc, item)
        data.append(item)
    return envelope(data, limit=limit, offset=offset, total=total,
                    database=database, collection=collection)
