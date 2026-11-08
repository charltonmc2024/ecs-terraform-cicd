"""Load MANIFEST.json and enforce the db/collection allowlist + path containment."""

from __future__ import annotations

import json
import os

from . import config
from .report import ReportError


def load_manifest():
    """Return the parsed MANIFEST.json dict; raise ReportError on any problem."""
    try:
        with open(config.MANIFEST_PATH, encoding="utf-8") as fh:
            manifest = json.load(fh)
    except FileNotFoundError:
        raise ReportError(f"MANIFEST.json not found at {config.MANIFEST_PATH}")
    except json.JSONDecodeError as exc:
        raise ReportError(f"MANIFEST.json is not valid JSON: {exc}")
    _check_allowlist(manifest)
    return manifest


def _check_allowlist(manifest) -> None:
    dbs = set(manifest.keys())
    allowed = set(config.ALLOWED_DBS)
    if dbs != allowed:
        raise ReportError(
            f"MANIFEST databases {sorted(dbs)} do not match allowlist {sorted(allowed)}"
        )
    for db, colls in manifest.items():
        expected = set(config.EXPECTED_COLLECTIONS[db])
        got = set(colls.keys())
        if got != expected:
            raise ReportError(
                f"MANIFEST collections for {db} {sorted(got)} != allowlist {sorted(expected)}"
            )


def entries(manifest):
    """Yield (db, collection, abs_file_path, expected_count), path-contained."""
    for db, colls in manifest.items():
        for coll, meta in colls.items():
            path = resolve_in_output(meta["file"])
            yield db, coll, path, int(meta["count"])


def resolve_in_output(filename: str) -> str:
    """Resolve filename against OUTPUT_DIR and ensure it stays inside it."""
    candidate = os.path.realpath(os.path.join(config.OUTPUT_DIR, filename))
    base = config.OUTPUT_DIR + os.sep
    if not (candidate == config.OUTPUT_DIR or candidate.startswith(base)):
        raise ReportError(f"path escapes approved output directory: {filename}")
    return candidate
