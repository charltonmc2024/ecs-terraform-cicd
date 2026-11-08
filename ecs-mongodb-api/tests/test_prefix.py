"""Offline tests for the API_PREFIX routing option. Fake in-memory DB only.

No MongoDB/Atlas connection, no network. MONGODB_URI is cleared for every test so
the app lifespan can never open a client. The subprocess test only imports the app
module locally to prove an invalid prefix stops startup.
"""

from __future__ import annotations

import os
import subprocess
import sys

import pytest
from fastapi.testclient import TestClient

from app import main as app_main
from app.config import MAX_API_PREFIX_LENGTH, normalize_api_prefix
from app.deps import get_database
from app.main import create_app, planned_routes

from .conftest import FakeDatabase

KEY = "test-key-not-a-secret"          # fake; matches the API_KEY set in conftest
HEADERS = {"x-api-key": KEY}
DATA_PATHS = ("/schools", "/users", "/classes", "/assignments")
PROTECTED = ("/ready",) + DATA_PATHS
PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


# ---------------------------------------------------------------- helpers ---
class ReadOnlySpy:
    """Wraps the fake DB/collections and records any call outside the read allowlist."""

    DB_ALLOWED = {"collection", "names", "ping", "close"}
    COLL_ALLOWED = {"count_documents", "find"}

    def __init__(self, inner, violations, allowed):
        self._inner = inner
        self._violations = violations
        self._allowed = allowed

    def __getattr__(self, name):
        if name not in self._allowed:
            self._violations.append(name)
            raise AssertionError(f"disallowed database call: {name}")
        target = getattr(self._inner, name)
        if name == "collection":
            return lambda resource: ReadOnlySpy(
                target(resource), self._violations, self.COLL_ALLOWED
            )
        return target


def make_client(monkeypatch, sample_data, prefix=None, violations=None):
    monkeypatch.delenv("MONGODB_URI", raising=False)
    if prefix is None:
        monkeypatch.delenv("API_PREFIX", raising=False)
    else:
        monkeypatch.setenv("API_PREFIX", prefix)
    app = create_app()
    db = FakeDatabase(sample_data)
    if violations is not None:
        db = ReadOnlySpy(db, violations, ReadOnlySpy.DB_ALLOWED)
    app.dependency_overrides[get_database] = lambda: db
    return TestClient(app, follow_redirects=False)


def expected_paths(prefix):
    return {
        ("GET", "/health"),
        ("GET", f"{prefix}/ready"),
        *{("GET", f"{prefix}{p}") for p in DATA_PATHS},
    }


# ------------------------------------------------- normalize_api_prefix -----
@pytest.mark.parametrize("raw, expected", [
    (None, ""), ("", ""), ("   ", ""), ("/", ""),
    ("/v1", "/v1"), ("/v1/", "/v1"), (" /v1 ", "/v1"),
    ("/api/v1", "/api/v1"), ("/v1.0", "/v1.0"), ("/demo-api", "/demo-api"),
])
def test_normalize_accepts_and_normalizes(raw, expected):
    assert normalize_api_prefix(raw) == expected


@pytest.mark.parametrize("raw", [
    "v1", "//", "/v1//", "/v1//x", "/v 1", "/../x", "/v1/../x", "/./x", "/v1/./x",
    "/v1?x=1", "/v1#x", "/%2e", "/%2e%2e/x", "/-v1", "/_v1", "/v1\nx", "/v1\\x",
    "/ünï", "/" + "a" * MAX_API_PREFIX_LENGTH,
])
def test_normalize_rejects_malformed(raw):
    with pytest.raises(ValueError) as excinfo:
        normalize_api_prefix(raw)
    assert str(excinfo.value) == "API_PREFIX is invalid"   # never echoes the value


def test_normalize_length_boundary():
    longest = "/" + "a" * (MAX_API_PREFIX_LENGTH - 1)
    assert normalize_api_prefix(longest) == longest


# ------------------------------------------------------ default (no prefix) --
def test_default_mode_routes_unchanged(monkeypatch, sample_data):
    c = make_client(monkeypatch, sample_data)
    assert c.get("/health").status_code == 200
    for path in PROTECTED:
        assert c.get(path, headers=HEADERS).status_code == 200, path
    assert set(planned_routes("")) == expected_paths("")


def test_default_mode_keeps_trailing_slash_redirect(monkeypatch, sample_data):
    c = make_client(monkeypatch, sample_data)
    assert c.get("/schools/", headers=HEADERS).status_code == 307


def test_default_mode_health_not_under_v1(monkeypatch, sample_data):
    c = make_client(monkeypatch, sample_data)
    assert c.get("/v1/health").status_code == 404


# ------------------------------------------------------ prefixed (/v1) mode --
def test_prefixed_routes_work(monkeypatch, sample_data):
    c = make_client(monkeypatch, sample_data, "/v1")
    for path in PROTECTED:
        assert c.get(f"/v1{path}", headers=HEADERS).status_code == 200, path


def test_prefixed_bodies_match_default_bodies(monkeypatch, sample_data):
    plain = make_client(monkeypatch, sample_data)
    prefixed = make_client(monkeypatch, sample_data, "/v1")
    for path in DATA_PATHS:
        assert prefixed.get(f"/v1{path}", headers=HEADERS).json() == \
            plain.get(path, headers=HEADERS).json(), path


def test_health_stays_unprefixed(monkeypatch, sample_data):
    c = make_client(monkeypatch, sample_data, "/v1")
    assert c.get("/health").status_code == 200
    assert c.get("/health").json() == {"status": "ok"}
    assert c.get("/v1/health").status_code == 404


def test_unprefixed_routes_are_404_in_prefixed_mode(monkeypatch, sample_data):
    c = make_client(monkeypatch, sample_data, "/v1")
    for path in PROTECTED:
        assert c.get(path, headers=HEADERS).status_code == 404, path


def test_prefixed_routes_require_api_key(monkeypatch, sample_data):
    c = make_client(monkeypatch, sample_data, "/v1")
    for path in PROTECTED:
        assert c.get(f"/v1{path}").status_code == 401, f"no key {path}"
        assert c.get(f"/v1{path}", headers={"x-api-key": "wrong"}).status_code == 401, \
            f"bad key {path}"


def test_trailing_slash_is_404_without_redirect_in_prefixed_mode(monkeypatch, sample_data):
    c = make_client(monkeypatch, sample_data, "/v1")
    for path in PROTECTED:
        r = c.get(f"/v1{path}/", headers=HEADERS)
        assert r.status_code == 404, path
        assert "location" not in r.headers, path


def test_trailing_slash_prefix_value_is_normalized(monkeypatch, sample_data):
    c = make_client(monkeypatch, sample_data, "/v1/")
    assert c.get("/v1/schools", headers=HEADERS).status_code == 200


def test_multi_segment_prefix(monkeypatch, sample_data):
    c = make_client(monkeypatch, sample_data, "/demo/v1")
    assert c.get("/demo/v1/users", headers=HEADERS).status_code == 200
    assert c.get("/health").status_code == 200


def test_docs_behavior_unchanged_in_both_modes(monkeypatch, sample_data):
    for prefix in (None, "/v1"):
        c = make_client(monkeypatch, sample_data, prefix)
        assert c.get("/docs").status_code == 200
        assert c.get("/openapi.json").status_code == 200


def test_openapi_paths_match_prefix(monkeypatch, sample_data):
    for prefix, mount in ((None, ""), ("/v1", "/v1")):
        c = make_client(monkeypatch, sample_data, prefix)
        paths = set(c.get("/openapi.json").json()["paths"])
        assert paths == {p for _m, p in expected_paths(mount)}


# --------------------------------------------------------- startup failures --
@pytest.mark.parametrize("bad", ["v1", "/v 1", "//", "/v1//x", "/../x", "/%2e"])
def test_create_app_rejects_invalid_prefix(monkeypatch, bad):
    monkeypatch.delenv("MONGODB_URI", raising=False)
    monkeypatch.setenv("API_PREFIX", bad)
    with pytest.raises(ValueError) as excinfo:
        create_app()
    assert str(excinfo.value) == "API_PREFIX is invalid"


def test_invalid_prefix_stops_process_startup(monkeypatch):
    env = {k: v for k, v in os.environ.items() if k != "MONGODB_URI"}
    env.update({"API_PREFIX": "not-a-valid-prefix", "API_KEY": KEY,
                "PYTHONDONTWRITEBYTECODE": "1"})
    result = subprocess.run(
        [sys.executable, "-c", "import app.main"],
        cwd=PROJECT_DIR, env=env, capture_output=True, text=True, timeout=60,
    )
    assert result.returncode != 0
    assert "API_PREFIX is invalid" in result.stderr
    assert "not-a-valid-prefix" not in result.stderr + result.stdout
    assert KEY not in result.stderr + result.stdout


def test_valid_prefix_process_imports_cleanly():
    env = {k: v for k, v in os.environ.items() if k != "MONGODB_URI"}
    env.update({"API_PREFIX": "/v1", "API_KEY": KEY, "PYTHONDONTWRITEBYTECODE": "1"})
    result = subprocess.run(
        [sys.executable, "-c", "import app.main"],
        cwd=PROJECT_DIR, env=env, capture_output=True, text=True, timeout=60,
    )
    assert result.returncode == 0, result.stderr[-300:]


# --------------------------------------------------- duplicate registration --
def test_planned_routes_are_unique_and_exact():
    for prefix in ("", "/v1", "/demo/v1"):
        planned = planned_routes(prefix)
        assert len(planned) == len(set(planned)), prefix
        assert set(planned) == expected_paths(prefix), prefix


def test_duplicate_registration_is_rejected(monkeypatch):
    from app.routers import schools
    monkeypatch.delenv("MONGODB_URI", raising=False)
    monkeypatch.delenv("API_PREFIX", raising=False)
    original = app_main._route_plan

    def doubled(prefix):
        return original(prefix) + [(schools.router, prefix)]

    monkeypatch.setattr(app_main, "_route_plan", doubled)
    with pytest.raises(RuntimeError, match="duplicate route registration"):
        create_app()


def test_each_app_has_independent_routes(monkeypatch, sample_data):
    a = make_client(monkeypatch, sample_data, "/v1")
    b = make_client(monkeypatch, sample_data)
    assert a.get("/v1/schools", headers=HEADERS).status_code == 200
    assert a.get("/schools", headers=HEADERS).status_code == 404
    assert b.get("/schools", headers=HEADERS).status_code == 200


# ----------------------------------------------------- read-only / no leaks --
def test_no_database_writes_in_either_mode(monkeypatch, sample_data):
    violations = []
    for prefix, mount in ((None, ""), ("/v1", "/v1")):
        c = make_client(monkeypatch, sample_data, prefix, violations)
        for path in PROTECTED:
            assert c.get(f"{mount}{path}", headers=HEADERS).status_code == 200
        assert c.get(f"{mount}/users?role=teacher&limit=1&offset=0",
                     headers=HEADERS).status_code == 200
    assert violations == []


def test_no_secrets_in_logs_or_responses(monkeypatch, sample_data, caplog):
    caplog.set_level("DEBUG")
    c = make_client(monkeypatch, sample_data, "/v1")
    with c:
        bodies = [
            c.get("/v1/schools", headers=HEADERS).text,
            c.get("/v1/schools", headers={"x-api-key": "wrong-key-value"}).text,
            c.get("/v1/schools").text,
            c.get("/v1/ready", headers=HEADERS).text,
            c.get("/nope").text,
        ]
    combined = "\n".join(bodies) + caplog.text
    assert KEY not in combined
    assert "wrong-key-value" not in combined
    assert "mongodb+srv://" not in combined and "mongodb://" not in combined
