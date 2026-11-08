"""Static guard: the app performs no MongoDB writes."""

import os
import tokenize

APP_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "app")

WRITE_APIS = (
    ".insert_one", ".insert_many", ".update_one", ".update_many", ".replace_one",
    ".delete_one", ".delete_many", ".drop", ".bulk_write", ".find_one_and",
    ".create_index", ".rename",
)


def _code_only(path):
    with open(path, "rb") as fh:
        toks = list(tokenize.tokenize(fh.readline))
    kept = [t.string for t in toks if t.type not in (tokenize.COMMENT, tokenize.STRING)]
    return " ".join(kept).replace(" . ", ".").replace(". ", ".").replace(" .", ".")


def test_no_write_apis_in_app():
    for root, _dirs, files in os.walk(APP_DIR):
        for name in files:
            if not name.endswith(".py"):
                continue
            code = _code_only(os.path.join(root, name))
            for bad in WRITE_APIS:
                assert bad not in code, f"{name}: write API {bad}"
