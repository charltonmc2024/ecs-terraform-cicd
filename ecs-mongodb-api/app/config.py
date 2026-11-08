"""Runtime configuration from environment variables. No secrets in source.

Local dev: set these in a shell or an untracked .env (see .env.example).
ECS: MONGODB_URI and API_KEY are injected from AWS Secrets Manager; DB names and
CORS origins are plain env/config.
"""

from __future__ import annotations

import os
import re
from dataclasses import dataclass, field
from typing import List


def _split_csv(value: str) -> List[str]:
    return [v.strip() for v in value.split(",") if v.strip()]


# API_PREFIX: optional URL path prefix for every route except /health (for example
# "/v1" behind CloudFront and the ALB). Validated strictly and ONLY at startup in
# create_app(); it is deliberately not validated inside get_settings(), which runs
# on every request and log record.
MAX_API_PREFIX_LENGTH = 64
_PREFIX_SEGMENT = r"[A-Za-z0-9][A-Za-z0-9._~-]*"
_PREFIX_PATTERN = re.compile(rf"/{_PREFIX_SEGMENT}(?:/{_PREFIX_SEGMENT})*")


def normalize_api_prefix(value: "str | None") -> str:
    """Return a safe route prefix: "" (no prefix) or a path like "/v1".

    Accepted: "" or "/" (no prefix); one trailing slash is removed ("/v1/" -> "/v1").
    Required: a leading slash and one or more ASCII path segments that each start
    with a letter or digit. Rejected with ValueError (message never echoes the
    value): missing leading slash, empty or dot segments, repeated slashes,
    whitespace inside, query/fragment characters, percent-encoding, and values
    longer than MAX_API_PREFIX_LENGTH.
    """
    raw = (value or "").strip()
    if raw in ("", "/"):
        return ""
    candidate = raw[:-1] if raw.endswith("/") else raw
    if len(candidate) > MAX_API_PREFIX_LENGTH or not _PREFIX_PATTERN.fullmatch(candidate):
        raise ValueError("API_PREFIX is invalid")
    return candidate


@dataclass(frozen=True)
class Settings:
    # Connection string (mongodb+srv://... with a READ-ONLY user). Never logged.
    mongodb_uri: str = field(default_factory=lambda: os.environ.get("MONGODB_URI", ""))
    teacher_student_db: str = field(
        default_factory=lambda: os.environ.get("TEACHER_STUDENT_DB", "teacher_student_db")
    )
    admin_staff_db: str = field(
        default_factory=lambda: os.environ.get("ADMIN_STAFF_DB", "admin_staff_mongodb")
    )
    api_key: str = field(default_factory=lambda: os.environ.get("API_KEY", ""))
    cors_allow_origins: List[str] = field(
        default_factory=lambda: _split_csv(os.environ.get("CORS_ALLOW_ORIGINS", ""))
    )
    # Raw API_PREFIX; normalized and validated once at startup (create_app).
    api_prefix: str = field(default_factory=lambda: os.environ.get("API_PREFIX", ""))
    port: int = field(default_factory=lambda: int(os.environ.get("PORT", "8080")))
    server_selection_timeout_ms: int = field(
        default_factory=lambda: int(os.environ.get("MONGO_SERVER_SELECTION_TIMEOUT_MS", "5000"))
    )


def get_settings() -> Settings:
    return Settings()
