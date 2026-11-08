HEADERS = {"x-api-key": "test-key-not-a-secret"}


def _ids(resp):
    return [d["id"] for d in resp.json()["data"]]


def test_schools_shape_and_no_pii(client):
    r = client.get("/schools", headers=HEADERS)
    assert r.status_code == 200
    body = r.json()
    assert body["meta"] == {"database": "admin_staff_mongodb", "collection": "school_collection"}
    s = body["data"][0]
    assert s["school_name"] == "Synthetic School 1"
    assert "email" not in s and "password" not in s


def test_users_no_auth_fields_and_role_filter(client):
    r = client.get("/users", headers=HEADERS)
    assert r.status_code == 200
    for u in r.json()["data"]:
        for bad in ("email", "password", "auth0_user_id", "auth_provider", "profile_picture"):
            assert bad not in u
    teachers = client.get("/users?role=teacher", headers=HEADERS).json()["data"]
    assert all(u["role"] == "teacher" for u in teachers)
    assert len(teachers) == 1


def test_classes_embedded_reduced(client):
    r = client.get("/classes", headers=HEADERS)
    assert r.status_code == 200
    c = r.json()["data"][0]
    assert c["class_code"] == "SYN001"
    assert "email" not in c["teacher"] and "auth0_user_id" not in c["teacher"]
    for st in c["students"]:
        assert "email" not in st and "auth0_user_id" not in st
        assert set(st.keys()) <= {"id", "first_name", "last_name", "status"}


def test_assignments_omit_questions(client):
    r = client.get("/assignments", headers=HEADERS)
    assert r.status_code == 200
    a = r.json()["data"][0]
    assert a["title"] == "Synthetic Assignment 1"
    assert "questions" not in a


def test_pagination_limits(client):
    r = client.get("/users?limit=1&offset=0", headers=HEADERS)
    body = r.json()
    assert body["pagination"]["limit"] == 1
    assert body["pagination"]["count"] == 1
    assert body["pagination"]["total"] == 2
