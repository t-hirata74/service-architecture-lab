def test_health_ok(client) -> None:
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json() == {"ok": True}


def test_health_needs_no_token(client) -> None:
    # /health は監視用なのでトークン不要 (eta / demand-forecast とは別扱い)。
    r = client.get("/health")
    assert r.status_code == 200
