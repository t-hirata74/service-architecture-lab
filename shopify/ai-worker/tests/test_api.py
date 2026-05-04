"""ai-worker API smoke tests + deterministic mock assertions."""

from fastapi.testclient import TestClient

from app.config import get_settings
from app.main import app


client = TestClient(app)


def auth_headers() -> dict[str, str]:
    return {"X-Internal-Token": get_settings().internal_token}


def test_health() -> None:
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json() == {"status": "ok"}


def test_recommend_requires_internal_token() -> None:
    r = client.post("/recommend", json={"shop_id": 1, "product_id": 1, "candidate_product_ids": [2, 3]})
    assert r.status_code == 401


def test_recommend_returns_deterministic_subset() -> None:
    body = {"shop_id": 1, "product_id": 10, "candidate_product_ids": [10, 11, 12, 13, 14], "limit": 3}
    r1 = client.post("/recommend", json=body, headers=auth_headers())
    r2 = client.post("/recommend", json=body, headers=auth_headers())
    assert r1.status_code == 200
    assert r1.json() == r2.json()
    payload = r1.json()
    assert payload["product_id"] == 10
    assert 10 not in payload["related"]
    assert len(payload["related"]) == 3
    assert set(payload["related"]).issubset({11, 12, 13, 14})


def test_summarize_reviews_zero_case() -> None:
    r = client.post("/summarize-reviews", json={"product_id": 1, "review_count": 0}, headers=auth_headers())
    assert r.status_code == 200
    assert r.json()["summary"] == "No reviews yet."


def test_summarize_reviews_nonzero() -> None:
    r = client.post("/summarize-reviews", json={"product_id": 1, "review_count": 12}, headers=auth_headers())
    assert r.status_code == 200
    assert "12" in r.json()["summary"]


def test_forecast_demand_moving_average_x1_2() -> None:
    r = client.post("/forecast-demand", json={"variant_id": 1, "last_n_days_sales": [10, 10, 10]}, headers=auth_headers())
    assert r.status_code == 200
    assert r.json()["forecast_units"] == 12  # 10 * 1.2


def test_forecast_demand_empty_input() -> None:
    r = client.post("/forecast-demand", json={"variant_id": 1, "last_n_days_sales": []}, headers=auth_headers())
    assert r.status_code == 200
    assert r.json()["forecast_units"] == 0
