_ETA_BODY = {
    "pickup_lat": 37.78,
    "pickup_lng": -122.41,
    "dropoff_lat": 37.79,
    "dropoff_lng": -122.40,
}


def test_eta_requires_token(client) -> None:
    r = client.post("/eta", json=_ETA_BODY)
    assert r.status_code == 401


def test_eta_invalid_token(client) -> None:
    r = client.post("/eta", headers={"X-Internal-Token": "wrong"}, json=_ETA_BODY)
    assert r.status_code == 401


def test_demand_forecast_requires_token(client) -> None:
    r = client.post("/demand-forecast", json={"h3_cell": "8928308280fffff"})
    assert r.status_code == 401
