from fastapi.testclient import TestClient

from main import app

client = TestClient(app)
AUTH = {"X-Internal-Token": "dev-internal-token"}


def test_health_is_public():
    res = client.get("/health")
    assert res.status_code == 200
    assert res.json() == {"ok": True}


def test_triage_requires_internal_token():
    assert client.post("/triage", json={"title": "x"}).status_code == 401
    res = client.post(
        "/triage", json={"title": "x"}, headers={"X-Internal-Token": "wrong"}
    )
    assert res.status_code == 401


def test_triage_urgent_keywords():
    res = client.post(
        "/triage", json={"title": "App crash on login"}, headers=AUTH
    )
    assert res.status_code == 200
    body = res.json()
    assert body["priority"] == 1
    assert "bug" in body["labels"]
    assert "crash" in body["reason"]


def test_triage_docs_keywords():
    res = client.post(
        "/triage", json={"title": "Fix typo in README"}, headers=AUTH
    )
    body = res.json()
    assert body["priority"] == 4
    assert body["labels"] == ["docs"]


def test_triage_combines_labels_first_rule_wins_priority():
    res = client.post(
        "/triage",
        json={"title": "Error page is slow", "description": "timeout happens"},
        headers=AUTH,
    )
    body = res.json()
    assert body["priority"] == 2
    assert body["labels"] == ["bug", "performance"]


def test_triage_default_medium():
    res = client.post(
        "/triage", json={"title": "Improve onboarding flow"}, headers=AUTH
    )
    body = res.json()
    assert body["priority"] == 3
    assert body["labels"] == []


def test_duplicates_matches_similar_titles():
    res = client.post(
        "/duplicates",
        json={
            "title": "Login page crashes on submit",
            "candidates": [
                {"id": 1, "title": "Login page crashes when submitting"},
                {"id": 2, "title": "Dark mode for settings"},
            ],
        },
        headers=AUTH,
    )
    assert res.status_code == 200
    assert res.json()["duplicate_ids"] == [1]


def test_duplicates_empty_candidates():
    res = client.post(
        "/duplicates", json={"title": "anything", "candidates": []}, headers=AUTH
    )
    assert res.json()["duplicate_ids"] == []


def test_duplicates_caps_at_five():
    candidates = [
        {"id": i, "title": f"Login crashes on submit {i}"} for i in range(10)
    ]
    res = client.post(
        "/duplicates",
        json={"title": "Login crashes on submit", "candidates": candidates},
        headers=AUTH,
    )
    assert len(res.json()["duplicate_ids"]) == 5
