"""SHA-256 file integrity verification against a separately approved baseline.

The baseline (import_tool/baseline.sha256) is created only by a separate,
explicitly-approved `--write-baseline` action — NEVER automatically. An import is
refused unless the current files match the approved baseline exactly.

Baseline format: one line per file, "<sha256>  <filename>" (filename relative to
output/), covering the 10 data files and MANIFEST.json.
"""

from __future__ import annotations

import hashlib
import os

from . import config
from .manifest import load_manifest, resolve_in_output
from .report import ReportError


def _sha256(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def files_to_hash(manifest):
    """Relative filenames to hash: the 10 data files plus MANIFEST.json."""
    names = ["MANIFEST.json"]
    for _db, colls in manifest.items():
        for _c, meta in colls.items():
            names.append(meta["file"])
    return sorted(set(names))


def compute_hashes():
    manifest = load_manifest()
    result = {}
    for name in files_to_hash(manifest):
        path = resolve_in_output(name)
        if not os.path.exists(path):
            raise ReportError(f"integrity: expected file missing: {name}")
        result[name] = _sha256(path)
    return result


def parse_baseline(text):
    baseline = {}
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) != 2:
            raise ReportError("baseline line is malformed")
        digest, name = parts
        baseline[name] = digest
    return baseline


def verify_against_baseline():
    """Return (ok, problems). Fail if baseline missing or any mismatch/extra/missing."""
    if not os.path.exists(config.BASELINE_PATH):
        raise ReportError(
            "no approved SHA-256 baseline found (import is refused). "
            "A baseline must be created by a separate, explicitly-approved step."
        )
    with open(config.BASELINE_PATH, encoding="utf-8") as fh:
        baseline = parse_baseline(fh.read())
    current = compute_hashes()
    problems = []
    for name, digest in sorted(baseline.items()):
        if name not in current:
            problems.append(f"baseline file missing on disk: {name}")
        elif current[name] != digest:
            problems.append(f"hash mismatch: {name}")
    for name in sorted(current):
        if name not in baseline:
            problems.append(f"unexpected file not in baseline: {name}")
    return (len(problems) == 0, problems)


def render_baseline_text():
    """Text for a future, approved baseline write. Not written here."""
    current = compute_hashes()
    return "".join(f"{current[name]}  {name}\n" for name in sorted(current))
