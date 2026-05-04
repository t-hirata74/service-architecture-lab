def test_summarize_requires_token(client) -> None:
    r = client.post("/summarize", json={"messages": []})
    assert r.status_code == 401


def test_moderate_requires_token(client) -> None:
    r = client.post("/moderate", json={"body": "hello"})
    assert r.status_code == 401


def test_summarize_invalid_token(client) -> None:
    r = client.post(
        "/summarize",
        headers={"X-Internal-Token": "wrong"},
        json={"messages": []},
    )
    assert r.status_code == 401
