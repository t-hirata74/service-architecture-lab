"""ADR 0003: /summarize の決定性と Bearer 認証を fixate する。"""

import pytest
from fastapi.testclient import TestClient

from app.config import get_settings
from app.main import app


@pytest.fixture
def client() -> TestClient:
    get_settings.cache_clear()
    return TestClient(app)


@pytest.fixture
def auth_headers() -> dict[str, str]:
    return {"Authorization": f"Bearer {get_settings().internal_token}"}


def test_health(client: TestClient) -> None:
    res = client.get("/health")
    assert res.status_code == 200
    assert res.json() == {"status": "ok"}


def test_summarize_requires_bearer(client: TestClient) -> None:
    res = client.post(
        "/summarize",
        json={"meeting_id": 1, "recording_id": 1, "transcript_seed": "x"},
    )
    assert res.status_code == 401


def test_summarize_rejects_wrong_token(client: TestClient) -> None:
    res = client.post(
        "/summarize",
        headers={"Authorization": "Bearer wrong"},
        json={"meeting_id": 1, "recording_id": 1, "transcript_seed": "x"},
    )
    assert res.status_code == 401


def test_summarize_returns_body_and_hash(client: TestClient, auth_headers: dict[str, str]) -> None:
    res = client.post(
        "/summarize",
        headers=auth_headers,
        json={"meeting_id": 7, "recording_id": 11, "transcript_seed": "weekly-sync"},
    )
    assert res.status_code == 200
    data = res.json()
    assert "[mock summary]" in data["body"]
    assert len(data["input_hash"]) == 64  # sha256 hex


def test_summarize_is_deterministic(client: TestClient, auth_headers: dict[str, str]) -> None:
    """ADR 0003: 同じ transcript_seed なら同じ body / input_hash。"""
    payload = {"meeting_id": 1, "recording_id": 1, "transcript_seed": "stable-seed"}
    a = client.post("/summarize", headers=auth_headers, json=payload).json()
    b = client.post("/summarize", headers=auth_headers, json=payload).json()
    assert a == b


def test_summarize_changes_with_seed(client: TestClient, auth_headers: dict[str, str]) -> None:
    a = client.post(
        "/summarize",
        headers=auth_headers,
        json={"meeting_id": 1, "recording_id": 1, "transcript_seed": "alpha"},
    ).json()
    b = client.post(
        "/summarize",
        headers=auth_headers,
        json={"meeting_id": 1, "recording_id": 1, "transcript_seed": "beta"},
    ).json()
    assert a["input_hash"] != b["input_hash"]


def test_summarize_validates_payload(client: TestClient, auth_headers: dict[str, str]) -> None:
    res = client.post(
        "/summarize",
        headers=auth_headers,
        json={"meeting_id": 1, "recording_id": 1, "transcript_seed": ""},
    )
    assert res.status_code == 422
