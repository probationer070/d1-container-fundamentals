from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_root():
    r = client.get("/")
    assert r.status_code == 200
    assert r.json()["service"] == "d1-health-api"


def test_healthz_is_live():
    r = client.get("/healthz")
    assert r.status_code == 200
    assert r.json()["status"] == "ok"
    assert "uptime_seconds" in r.json()


def test_readyz_is_ready():
    r = client.get("/readyz")
    assert r.status_code == 200
    assert r.json()["status"] == "ready"


def test_version_reports_env():
    r = client.get("/version")
    assert r.status_code == 200
    body = r.json()
    assert "version" in body and "git_sha" in body
