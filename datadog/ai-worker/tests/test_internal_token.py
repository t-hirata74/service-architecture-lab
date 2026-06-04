def test_detect_requires_token(client):
    res = client.post("/detect-anomaly", json={"points": []})
    assert res.status_code == 401


def test_forecast_requires_token(client):
    res = client.post("/forecast", json={"points": []})
    assert res.status_code == 401


def test_wrong_token_rejected(client):
    res = client.post("/detect-anomaly", json={"points": []}, headers={"X-Internal-Token": "nope"})
    assert res.status_code == 401
