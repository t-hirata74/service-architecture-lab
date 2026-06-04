def _pts(values):
    return {"points": [{"value": v} for v in values]}


def test_flags_outlier(client, auth):
    # 1 が十分多く並ぶ中に 100 が 1 つ → 異常 (z-score は標本が小さいと単一極値が自己マスク
    # するため、baseline を 20 点にして |z|>3 を成立させる)。
    values = [1] * 20 + [100]
    body = _pts(values)
    body["k"] = 3.0
    res = client.post("/detect-anomaly", json=body, headers=auth)
    assert res.status_code == 200
    out = res.json()
    idxs = [a["index"] for a in out["anomalies"]]
    assert 20 in idxs  # 100 の位置 (index 20)
    assert out["threshold"] > out["mean"]


def test_no_anomaly_when_flat(client, auth):
    res = client.post("/detect-anomaly", json=_pts([5, 5, 5, 5]), headers=auth)
    out = res.json()
    assert out["std"] == 0.0
    assert out["anomalies"] == []
    assert out["threshold"] == 5.0  # std=0 → mean


def test_empty_points(client, auth):
    res = client.post("/detect-anomaly", json=_pts([]), headers=auth)
    assert res.status_code == 200
    assert res.json()["anomalies"] == []
