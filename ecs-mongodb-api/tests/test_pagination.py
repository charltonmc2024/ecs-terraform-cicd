from app.pagination import clamp_limit, clamp_offset, envelope, DEFAULT_LIMIT, MAX_LIMIT


def test_clamp_limit():
    assert clamp_limit(None) == DEFAULT_LIMIT
    assert clamp_limit(0) == 1
    assert clamp_limit(5) == 5
    assert clamp_limit(1000) == MAX_LIMIT


def test_clamp_offset():
    assert clamp_offset(None) == 0
    assert clamp_offset(-3) == 0
    assert clamp_offset(7) == 7


def test_envelope_shape():
    env = envelope([{"id": "1"}], limit=20, offset=0, total=1,
                   database="teacher_student_db", collection="user_collection")
    assert env["pagination"] == {"limit": 20, "offset": 0, "count": 1, "total": 1}
    assert env["meta"] == {"database": "teacher_student_db", "collection": "user_collection"}
    assert env["data"] == [{"id": "1"}]
