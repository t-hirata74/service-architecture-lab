def _pts(values):
    return {"points": [{"value": v} for v in values]}


def test_linear_trend_extrapolates(client, auth):
    # y = x (0,1,2,3,4) → 次の 3 点は 5,6,7
    body = _pts([0, 1, 2, 3, 4])
    body["horizon"] = 3
    res = client.post("/forecast", json=body, headers=auth)
    assert res.status_code == 200
    out = res.json()
    assert out["slope"] == 1.0
    assert out["forecast"] == [5.0, 6.0, 7.0]


def test_single_point_repeats(client, auth):
    body = _pts([42])
    body["horizon"] = 2
    res = client.post("/forecast", json=body, headers=auth)
    out = res.json()
    assert out["forecast"] == [42.0, 42.0]
