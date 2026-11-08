"""Secure, in-memory Atlas client construction. NO URI is accepted anywhere.

The client is built from fixed, non-secret parts (username, host) plus the
password read from ATLAS_PASSWORD. Credentials are passed as pymongo kwargs,
never interpolated into a connection string, so no credential is ever formatted
into a loggable value. TLS with certificate verification is mandatory.

pymongo is imported lazily here so that the offline modes (validate, integrity)
never import a database driver and can never touch the network.
"""

from __future__ import annotations

import os

from . import config
from .report import ReportError


def _password_or_abort() -> str:
    pw = os.environ.get(config.PASSWORD_ENV)
    if not pw:
        raise ReportError(f"{config.PASSWORD_ENV} is not set; refusing to connect.")
    return pw


def host_is_approved(host: str) -> bool:
    if host != config.APPROVED_HOST:
        return False
    lowered = host.lower()
    return not any(bad in lowered for bad in config.DENY_HOST_SUBSTRINGS)


def build_client():
    """Return a pymongo MongoClient to the approved host over TLS.

    Caller owns closing the client. This function performs NO I/O beyond what
    pymongo does lazily; it does not ping. Host is validated before construction.
    """
    if not host_is_approved(config.APPROVED_HOST):
        raise ReportError("target host failed the allowlist/denylist check")

    password = _password_or_abort()
    try:
        from pymongo import MongoClient
    except Exception:
        raise ReportError("pymongo is required for this mode but is not available.")

    # mongodb+srv => TLS by default; we still force tls=True and certificate
    # verification on, and never set any insecure TLS option.
    client = MongoClient(
        host=f"mongodb+srv://{config.APPROVED_HOST}/",
        username=config.ATLAS_USER,
        password=password,            # kwarg; never concatenated into a URI string
        tls=True,
        tlsAllowInvalidCertificates=False,
        tlsAllowInvalidHostnames=False,
        serverSelectionTimeoutMS=5000,
        appname="eruditiontx-dev-seed-importer",
    )
    return client
