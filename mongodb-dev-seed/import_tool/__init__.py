"""Offline-first, safety-gated synthetic-data import tool (design Rev 2).

Modes: validate (default, offline), integrity (offline), preflight (read-only),
import (insert-only, double-confirmed, fail-closed), verify (read-only).
No module here writes baseline.sha256 or performs any destructive operation.
"""
