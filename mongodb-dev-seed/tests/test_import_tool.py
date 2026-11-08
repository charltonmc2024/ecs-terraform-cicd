"""Offline unit tests for import_tool. No network, no real pymongo client.

Run (needs bson.json_util; use the venv interpreter):
  python3 -m unittest tests.test_import_tool -v   (from mongodb-dev-seed/)
"""

from __future__ import annotations

import io
import os
import sys
import unittest
from contextlib import redirect_stdout

SEED_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, SEED_DIR)

from import_tool import config          # noqa: E402
from import_tool import manifest        # noqa: E402
from import_tool import validate        # noqa: E402
from import_tool import integrity       # noqa: E402
from import_tool import report          # noqa: E402
from import_tool import connection      # noqa: E402
from import_tool import preflight       # noqa: E402
from import_tool import importer        # noqa: E402
from import_tool import cli             # noqa: E402
from import_tool.report import ReportError  # noqa: E402


# --------------------------- fakes (no network) --------------------------- #
class FakeCollection:
    def __init__(self, docs=None, fail_on_insert=False):
        self._docs = list(docs or [])
        self.fail_on_insert = fail_on_insert
        self.inserted = []

    def count_documents(self, flt):
        return len(self._docs)

    def insert_many(self, docs, ordered=True):
        if self.fail_on_insert:
            raise RuntimeError("simulated insert failure")
        self.inserted.extend(docs)
        self._docs.extend(docs)

    def find(self, flt, proj=None):
        return iter(self._docs)


class FakeDB:
    def __init__(self, collections):
        self._c = collections

    def list_collection_names(self):
        return list(self._c.keys())

    def __getitem__(self, name):
        return self._c.setdefault(name, FakeCollection())


class FakeClient:
    def __init__(self, dbs):
        self._dbs = dbs
        self.closed = False

    def __getitem__(self, name):
        return self._dbs.setdefault(name, FakeDB({}))

    def close(self):
        self.closed = True


def empty_client():
    return FakeClient({
        config.TEACHER_STUDENT_DB: FakeDB({}),
        config.ADMIN_STAFF_DB: FakeDB({}),
    })


# ------------------------------- tests ------------------------------------ #
class TestManifest(unittest.TestCase):
    def test_load_and_allowlist(self):
        m = manifest.load_manifest()
        self.assertEqual(set(m.keys()), set(config.ALLOWED_DBS))
        total = sum(meta["count"] for db in m.values() for meta in db.values())
        self.assertEqual(total, config.EXPECTED_TOTAL_DOCS)

    def test_path_containment_rejects_escape(self):
        with self.assertRaises(ReportError):
            manifest.resolve_in_output("../generate.py")
        with self.assertRaises(ReportError):
            manifest.resolve_in_output("/etc/passwd")

    def test_entries_paths_inside_output(self):
        for _db, _c, path, _n in manifest.entries(manifest.load_manifest()):
            self.assertTrue(path.startswith(config.OUTPUT_DIR))


class TestValidate(unittest.TestCase):
    def test_validate_all_passes(self):
        ok, results = validate.validate_all()
        self.assertTrue(ok, [r for r in results if r[2] != "PASS"])
        total_row = [r for r in results if r[1] == "TOTAL"][0]
        self.assertEqual(total_row[2], "PASS")

    def test_json_util_required_fail_closed(self):
        # If bson.json_util import fails, validation must raise, not degrade.
        import builtins
        real_import = builtins.__import__

        def fake_import(name, *a, **k):
            if name == "bson" or name.startswith("bson."):
                raise ImportError("simulated missing bson")
            return real_import(name, *a, **k)

        builtins.__import__ = fake_import
        try:
            with self.assertRaises(ReportError):
                validate._require_json_util()
        finally:
            builtins.__import__ = real_import


class TestIntegrity(unittest.TestCase):
    def test_no_baseline_refuses(self):
        # baseline.sha256 must NOT exist yet (not written per restrictions).
        self.assertFalse(os.path.exists(config.BASELINE_PATH))
        with self.assertRaises(ReportError):
            integrity.verify_against_baseline()

    def test_compute_and_render_consistent(self):
        text = integrity.render_baseline_text()
        parsed = integrity.parse_baseline(text)
        current = integrity.compute_hashes()
        self.assertEqual(parsed, current)
        # includes MANIFEST + 10 files
        self.assertEqual(len(current), 11)


class TestHostGuard(unittest.TestCase):
    def test_approved_host(self):
        self.assertTrue(connection.host_is_approved(config.APPROVED_HOST))

    def test_rejects_other_hosts(self):
        for bad in ("localhost", "cluster.mathmattersqa.com",
                    "evil.mongodb.net", "10.0.0.5"):
            self.assertFalse(connection.host_is_approved(bad))


class TestPreflight(unittest.TestCase):
    def test_all_empty_passes(self):
        ok, results = preflight.run_preflight(empty_client())
        self.assertTrue(ok)

    def test_unexpected_collection_fails(self):
        client = FakeClient({
            config.TEACHER_STUDENT_DB: FakeDB({"rogue_collection": FakeCollection([{"x": 1}])}),
            config.ADMIN_STAFF_DB: FakeDB({}),
        })
        ok, results = preflight.run_preflight(client)
        self.assertFalse(ok)
        self.assertTrue(any("unexpected" in d for _s, v, d in results if v == "FAIL"))

    def test_nonempty_target_fails(self):
        client = FakeClient({
            config.TEACHER_STUDENT_DB: FakeDB({"user_collection": FakeCollection([{"_id": 1}])}),
            config.ADMIN_STAFF_DB: FakeDB({}),
        })
        ok, results = preflight.run_preflight(client)
        self.assertFalse(ok)

    def test_assert_collection_empty_raises(self):
        client = FakeClient({
            config.TEACHER_STUDENT_DB: FakeDB({"user_collection": FakeCollection([{"_id": 1}])}),
            config.ADMIN_STAFF_DB: FakeDB({}),
        })
        with self.assertRaises(ReportError):
            preflight.assert_collection_empty(client, config.TEACHER_STUDENT_DB, "user_collection")


class TestImporterFailClosed(unittest.TestCase):
    def test_import_without_execute_refuses(self):
        with self.assertRaises(ReportError):
            importer.run_import(empty_client(), execute=False, confirm=config.CONFIRM_PHRASE)

    def test_import_wrong_confirm_refuses(self):
        with self.assertRaises(ReportError):
            importer.run_import(empty_client(), execute=True, confirm="nope")

    def test_cli_import_missing_flags_fail_closed(self):
        # No --execute / --confirm: returns non-zero, no write path reached.
        buf = io.StringIO()
        with redirect_stdout(buf):
            rc = cli.main(["--mode", "import"])
        self.assertNotEqual(rc, 0)
        self.assertIn("REFUSED", buf.getvalue())

    def test_partial_import_reports_and_no_rollback(self):
        # Make the 3rd collection in order fail; assert partial reporting, no delete.
        fail_db, fail_coll = config.IMPORT_ORDER[2]
        dbs = {
            config.TEACHER_STUDENT_DB: FakeDB({}),
            config.ADMIN_STAFF_DB: FakeDB({}),
        }
        # Pre-make the failing collection as a failing one.
        dbs[fail_db]._c[fail_coll] = FakeCollection(fail_on_insert=True)
        client = FakeClient(dbs)
        buf = io.StringIO()
        with redirect_stdout(buf):
            with self.assertRaises(ReportError):
                importer.run_import(client, execute=True, confirm=config.CONFIRM_PHRASE)
        out = buf.getvalue()
        self.assertIn("POSSIBLE PARTIAL IMPORT", out)


class TestNoDestructiveAPIs(unittest.TestCase):
    def _code_only(self, path):
        """Return source with comments and string literals removed, so prose
        mentioning a method name (e.g. the docstring 'never upsert') does not
        trip the static check — only actual code tokens are inspected."""
        import io, tokenize
        with open(path, "rb") as fh:
            toks = list(tokenize.tokenize(fh.readline))
        kept = []
        for tok in toks:
            if tok.type in (tokenize.COMMENT, tokenize.STRING):
                continue
            kept.append(tok.string)
        return " ".join(kept)

    def test_importer_source_has_no_destructive_calls(self):
        code = self._code_only(os.path.join(SEED_DIR, "import_tool", "importer.py"))
        code = code.replace(" . ", ".").replace(". ", ".").replace(" .", ".")
        # Destructive / mutating call forms (method access or kwarg), not prose.
        for bad in (".drop", ".drop_collection", ".delete_one", ".delete_many",
                    ".replace_one", ".update_one", ".update_many", "upsert=",
                    ".find_one_and", ".bulk_write", ".drop_index", ".rename"):
            self.assertNotIn(bad, code, f"destructive API present: {bad}")
        # The only write call allowed is insert_many.
        self.assertIn(".insert_many", code)


class TestRedaction(unittest.TestCase):
    def test_password_and_user_redacted(self):
        os.environ["ATLAS_PASSWORD"] = "FAKEPW-shouldnotappear"
        try:
            text = report.redact(
                "conn mongodb+srv://eruditiontx_ecs_dev:FAKEPW-shouldnotappear@h/ x")
            self.assertNotIn("FAKEPW-shouldnotappear", text)
            self.assertNotIn("eruditiontx_ecs_dev", text)
            self.assertNotIn("FAKEPW", text)
        finally:
            del os.environ["ATLAS_PASSWORD"]


class TestConnectionNeedsPassword(unittest.TestCase):
    def test_missing_password_aborts(self):
        old = os.environ.pop("ATLAS_PASSWORD", None)
        try:
            with self.assertRaises(ReportError):
                connection._password_or_abort()
        finally:
            if old is not None:
                os.environ["ATLAS_PASSWORD"] = old


if __name__ == "__main__":
    unittest.main(verbosity=2)
