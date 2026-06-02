def test_eta_zero_distance_is_base_overhead(client, auth_headers) -> None:
    # pickup == dropoff なら距離 0、ETA は固定オーバーヘッドのみ。
    body = {
        "pickup_lat": 37.78,
        "pickup_lng": -122.41,
        "dropoff_lat": 37.78,
        "dropoff_lng": -122.41,
    }
    r = client.post("/eta", headers=auth_headers, json=body)
    assert r.status_code == 200
    data = r.json()
    assert data["distance_meters"] == 0
    assert data["eta_seconds"] == 60  # _BASE_OVERHEAD_S


def test_eta_increases_with_distance(client, auth_headers) -> None:
    near = {
        "pickup_lat": 37.78,
        "pickup_lng": -122.41,
        "dropoff_lat": 37.79,
        "dropoff_lng": -122.40,
    }
    far = {
        "pickup_lat": 37.78,
        "pickup_lng": -122.41,
        "dropoff_lat": 37.90,
        "dropoff_lng": -122.20,
    }
    rn = client.post("/eta", headers=auth_headers, json=near).json()
    rf = client.post("/eta", headers=auth_headers, json=far).json()
    assert rf["distance_meters"] > rn["distance_meters"]
    assert rf["eta_seconds"] > rn["eta_seconds"]


def test_eta_is_deterministic(client, auth_headers) -> None:
    body = {
        "pickup_lat": 37.78,
        "pickup_lng": -122.41,
        "dropoff_lat": 37.79,
        "dropoff_lng": -122.40,
    }
    a = client.post("/eta", headers=auth_headers, json=body).json()
    b = client.post("/eta", headers=auth_headers, json=body).json()
    assert a == b


def test_eta_rejects_out_of_range_coords(client, auth_headers) -> None:
    body = {
        "pickup_lat": 999.0,
        "pickup_lng": -122.41,
        "dropoff_lat": 37.79,
        "dropoff_lng": -122.40,
    }
    r = client.post("/eta", headers=auth_headers, json=body)
    assert r.status_code == 422
