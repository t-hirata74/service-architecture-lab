def test_health_no_token_required(client) -> None:
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json() == {"ok": True}
