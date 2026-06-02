def test_demand_forecast_shape(client, auth_headers) -> None:
    r = client.post(
        "/demand-forecast",
        headers=auth_headers,
        json={"h3_cell": "8928308280fffff"},
    )
    assert r.status_code == 200
    data = r.json()
    assert data["h3_cell"] == "8928308280fffff"
    assert 0.0 <= data["demand_index"] <= 1.0
    assert 1.0 <= data["surge_multiplier"] <= 2.0


def test_demand_forecast_is_deterministic_per_cell(client, auth_headers) -> None:
    body = {"h3_cell": "8928308280fffff"}
    a = client.post("/demand-forecast", headers=auth_headers, json=body).json()
    b = client.post("/demand-forecast", headers=auth_headers, json=body).json()
    assert a == b


def test_demand_forecast_varies_by_cell(client, auth_headers) -> None:
    a = client.post(
        "/demand-forecast", headers=auth_headers, json={"h3_cell": "8928308280fffff"}
    ).json()
    b = client.post(
        "/demand-forecast", headers=auth_headers, json={"h3_cell": "8928308281fffff"}
    ).json()
    assert a["demand_index"] != b["demand_index"]
