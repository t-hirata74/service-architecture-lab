"""calendly ai-worker `/recommend_slots` の deterministic mock テスト (zoom と同形)。"""

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)
TOKEN_HEADER = {"Authorization": "Bearer dev-internal-token"}

CANDIDATES = [
    {"start_at_utc": "2026-06-01T09:00:00Z", "end_at_utc": "2026-06-01T10:00:00Z"},
    {"start_at_utc": "2026-06-01T13:00:00Z", "end_at_utc": "2026-06-01T14:00:00Z"},
    {"start_at_utc": "2026-06-01T16:00:00Z", "end_at_utc": "2026-06-01T17:00:00Z"},
]


def test_health():
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json() == {"status": "ok"}


def test_recommend_requires_bearer():
    r = client.post(
        "/recommend_slots",
        json={"host_id": 1, "invitee_email": "x@example.com", "candidates": CANDIDATES},
    )
    assert r.status_code == 401


def test_recommend_rejects_wrong_token():
    r = client.post(
        "/recommend_slots",
        json={"host_id": 1, "invitee_email": "x@example.com", "candidates": CANDIDATES},
        headers={"Authorization": "Bearer wrong"},
    )
    assert r.status_code == 401


def test_recommend_returns_scored_slots():
    r = client.post(
        "/recommend_slots",
        json={"host_id": 1, "invitee_email": "x@example.com", "candidates": CANDIDATES},
        headers=TOKEN_HEADER,
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert "recommended" in body and "input_hash" in body
    assert len(body["recommended"]) == 3  # 候補 3 件 → 上位 5 件 cap で 3 件
    for slot in body["recommended"]:
        assert 0.0 <= slot["score"] <= 1.0
        assert slot["reason_code"] in {"morning_focus", "after_lunch", "end_of_day", "midweek_buffer"}


def test_recommend_is_deterministic():
    payload = {"host_id": 42, "invitee_email": "alice@example.com", "candidates": CANDIDATES}
    r1 = client.post("/recommend_slots", json=payload, headers=TOKEN_HEADER)
    r2 = client.post("/recommend_slots", json=payload, headers=TOKEN_HEADER)
    assert r1.json() == r2.json()


def test_recommend_changes_with_input():
    a = client.post(
        "/recommend_slots",
        json={"host_id": 1, "invitee_email": "alice@example.com", "candidates": CANDIDATES},
        headers=TOKEN_HEADER,
    ).json()
    b = client.post(
        "/recommend_slots",
        json={"host_id": 1, "invitee_email": "bob@example.com", "candidates": CANDIDATES},
        headers=TOKEN_HEADER,
    ).json()
    assert a["input_hash"] != b["input_hash"]


def test_recommend_validates_payload():
    r = client.post(
        "/recommend_slots",
        json={"host_id": 1, "invitee_email": "", "candidates": []},
        headers=TOKEN_HEADER,
    )
    assert r.status_code == 422
