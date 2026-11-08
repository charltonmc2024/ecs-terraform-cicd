"""Regression tests for the offline test environment (see tests/conftest.py).

conftest.py sanitizes the process environment before the app is imported, so these
hold no matter what the developer exported in the shell.
"""

import os

from app.config import get_settings

FAKE_TEST_KEY = "test-key-not-a-secret"


def test_default_empty_api_prefix():
    assert "API_PREFIX" not in os.environ
    assert get_settings().api_prefix == ""


def test_mongodb_uri_is_absent():
    assert "MONGODB_URI" not in os.environ
    assert get_settings().mongodb_uri == ""


def test_api_key_is_the_known_fake_value():
    assert os.environ["API_KEY"] == FAKE_TEST_KEY
    assert get_settings().api_key == FAKE_TEST_KEY
