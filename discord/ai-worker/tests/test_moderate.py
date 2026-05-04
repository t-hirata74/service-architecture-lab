def test_moderate_clean_text(client, auth_headers) -> None:
    r = client.post(
        "/moderate", headers=auth_headers, json={"body": "good morning everyone"}
    )
    assert r.status_code == 200
    body = r.json()
    assert isinstance(body["flagged"], bool)
    assert 0.0 <= body["score"] <= 1.0


def test_moderate_flagged_term(client, auth_headers) -> None:
    r = client.post(
        "/moderate", headers=auth_headers, json={"body": "this is a spam message"}
    )
    assert r.status_code == 200
    body = r.json()
    assert body["flagged"] is True
    assert any("banned_terms" in reason for reason in body["reasons"])


def test_moderate_deterministic(client, auth_headers) -> None:
    payload = {"body": "hello world"}
    a = client.post("/moderate", headers=auth_headers, json=payload).json()
    b = client.post("/moderate", headers=auth_headers, json=payload).json()
    assert a == b


def test_moderate_clean_text_never_flagged(client, auth_headers) -> None:
    # Score is hash-derived noise; it must not drive flagged on its own,
    # otherwise innocent messages would randomly trip the filter.
    samples = ["hi", "good morning", "ship it", "lunch?", "deploy ok"]
    for body in samples:
        r = client.post("/moderate", headers=auth_headers, json={"body": body}).json()
        assert r["flagged"] is False, (body, r)


def test_moderate_rejects_oversize_body(client, auth_headers) -> None:
    r = client.post(
        "/moderate", headers=auth_headers, json={"body": "x" * 5000}
    )
    assert r.status_code == 422
