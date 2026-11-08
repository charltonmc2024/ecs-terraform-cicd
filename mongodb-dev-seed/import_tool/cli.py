"""Command-line entry point. Default mode is offline validate.

Connecting modes (preflight/import/verify) import pymongo lazily and read the
password from ATLAS_PASSWORD. The import mode FAILS CLOSED unless BOTH --execute
and the exact --confirm phrase are supplied; there is no silent dry-run fallback.

This CLI never accepts a connection URI and never prints credentials.
"""

from __future__ import annotations

import argparse
import sys

from . import config
from .report import line, section, redact, ReportError


def _print_results(results):
    for row in results:
        if len(row) == 4:
            db, coll, verdict, detail = row
            line(f"{verdict:5} {db}.{coll}: {detail}")
        else:
            scope, verdict, detail = row
            line(f"{verdict:5} {scope}: {detail}")


def mode_validate() -> int:
    from .validate import validate_all
    section("VALIDATE (offline, Extended JSON via bson.json_util)")
    ok, results = validate_all()
    _print_results(results)
    line("RESULT: PASS" if ok else "RESULT: FAIL")
    return 0 if ok else 1


def mode_integrity() -> int:
    from .integrity import verify_against_baseline
    section("INTEGRITY (offline, SHA-256 vs approved baseline)")
    ok, problems = verify_against_baseline()
    if ok:
        line("RESULT: PASS (all files match the approved baseline)")
        return 0
    for p in problems:
        line(f"FAIL  {p}")
    line("RESULT: FAIL")
    return 1


def mode_preflight() -> int:
    from .connection import build_client
    from .preflight import run_preflight
    section("PREFLIGHT (read-only: host/TLS, collection allowlist, empty check)")
    client = build_client()
    try:
        ok, results = run_preflight(client)
    finally:
        client.close()
    _print_results(results)
    line("RESULT: PASS" if ok else "RESULT: FAIL")
    return 0 if ok else 1


def mode_import(args) -> int:
    section("IMPORT (insert-only; requires --execute and exact --confirm)")
    # FAIL CLOSED before doing anything else.
    if not args.execute or args.confirm != config.CONFIRM_PHRASE:
        line("REFUSED: import requires BOTH --execute and the exact --confirm phrase.")
        line("No connection or write was attempted. (No dry-run fallback.)")
        return 2
    # Integrity gate: refuse without an approved baseline match.
    from .integrity import verify_against_baseline
    ok, problems = verify_against_baseline()
    if not ok:
        for p in problems:
            line(f"FAIL  {p}")
        line("REFUSED: dataset does not match the approved SHA-256 baseline.")
        return 1
    from .connection import build_client
    from .preflight import run_preflight
    from .importer import run_import
    client = build_client()
    try:
        pf_ok, pf_results = run_preflight(client)
        _print_results(pf_results)
        if not pf_ok:
            line("REFUSED: preflight failed; no write attempted.")
            return 1
        status = run_import(client, execute=True, confirm=args.confirm)
        line("IMPORT COMPLETE:")
        for (db, coll), state in status.items():
            line(f"  {db}.{coll}: {state}")
    finally:
        client.close()
    return 0


def mode_verify() -> int:
    from .connection import build_client
    from .verify import run_verify
    section("VERIFY (read-only: counts vs MANIFEST + cross-references)")
    client = build_client()
    try:
        ok, results = run_verify(client)
    finally:
        client.close()
    _print_results(results)
    line("RESULT: PASS" if ok else "RESULT: FAIL")
    return 0 if ok else 1


def build_parser():
    p = argparse.ArgumentParser(
        prog="import_tool",
        description="Offline-first, safety-gated synthetic-data import tool.",
    )
    p.add_argument("--mode", choices=["validate", "integrity", "preflight", "import", "verify"],
                   default="validate", help="default: validate (offline)")
    p.add_argument("--execute", action="store_true",
                   help="required (with --confirm) to actually import")
    p.add_argument("--confirm", default="",
                   help=f'must equal exactly: "{config.CONFIRM_PHRASE}"')
    return p


def main(argv=None) -> int:
    args = build_parser().parse_args(argv)
    try:
        if args.mode == "validate":
            return mode_validate()
        if args.mode == "integrity":
            return mode_integrity()
        if args.mode == "preflight":
            return mode_preflight()
        if args.mode == "import":
            return mode_import(args)
        if args.mode == "verify":
            return mode_verify()
    except ReportError as exc:
        # Already-redacted message.
        print(redact(f"ERROR: {exc}"))
        return 1
    except Exception as exc:  # pylint: disable=broad-except
        # Sanitize any unexpected error so no credential can leak.
        print(redact(f"UNEXPECTED ERROR: {type(exc).__name__}: {exc}"))
        return 1
    return 1


if __name__ == "__main__":
    sys.exit(main())
