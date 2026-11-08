"""Structured reporting with mandatory secret redaction.

Every line the tool emits (stdout, logged errors, the final report, and any
sanitized exception text) passes through redact(). It scrubs the ATLAS_PASSWORD
value, the fixed username, and any mongodb connection-string fragment so no
credential can appear in logs, exceptions, files, or test output.
"""

from __future__ import annotations

import os
import re

from . import config

_MONGO_URI_RE = re.compile(r"mongodb(\+srv)?://[^\s'\"]+", re.IGNORECASE)


def _password() -> str:
    return os.environ.get(config.PASSWORD_ENV, "")


def redact(text: str) -> str:
    """Remove any credential material from a string before it is shown/stored."""
    if not isinstance(text, str):
        text = str(text)
    pw = _password()
    if pw:
        text = text.replace(pw, "***REDACTED***")
    # Username is non-secret but we still mask it to avoid building a cred pair in logs.
    text = text.replace(config.ATLAS_USER, "***USER***")
    # Any full mongodb URI fragment -> host-only marker.
    text = _MONGO_URI_RE.sub("mongodb+srv://***REDACTED***", text)
    return text


def line(msg: str) -> None:
    print(redact(msg))


def section(title: str) -> None:
    print(redact(f"\n=== {title} ==="))


class ReportError(Exception):
    """Raised with an already-redacted message; safe to display."""

    def __init__(self, msg: str):
        super().__init__(redact(msg))
