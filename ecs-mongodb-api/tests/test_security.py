def test_health_is_unauthenticated(client):
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json() == {"status": "ok"}


def test_ready_requires_api_key(client):
    assert client.get("/ready").status_code == 401
    r = client.get("/ready", headers={"x-api-key": "test-key-not-a-secret"})
    assert r.status_code == 200
    assert r.json()["status"] == "ready"


def test_data_endpoints_require_api_key(client):
    for path in ("/schools", "/users", "/classes", "/assignments"):
        assert client.get(path).status_code == 401, path


def test_wrong_api_key_rejected(client):
    assert client.get("/schools", headers={"x-api-key": "wrong"}).status_code == 401
