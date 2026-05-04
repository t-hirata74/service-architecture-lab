async def test_health(client):
    res = await client.get("/health")
    assert res.status_code == 200
    assert res.json() == {"ok": True}


async def test_summarize_requires_internal_token(client):
    res = await client.post("/summarize", json={"title": "x", "body": "y"})
    assert res.status_code == 401


async def test_summarize_returns_keywords(client):
    res = await client.post(
        "/summarize",
        json={
            "title": "FastAPI tutorial for Python beginners",
            "body": "Python python python tutorial fastapi async tutorial",
        },
        headers={"X-Internal-Token": "dev-internal-token"},
    )
    assert res.status_code == 200
    body = res.json()
    assert "python" in body["keywords"]
    assert body["summary"].startswith("TL;DR")


async def test_summarize_empty_body(client):
    res = await client.post(
        "/summarize",
        json={"title": "the a an", "body": ""},
        headers={"X-Internal-Token": "dev-internal-token"},
    )
    assert res.status_code == 200
    assert res.json()["keywords"] == []


async def test_related_returns_three(client):
    res = await client.post(
        "/related",
        json={"subreddit": "python"},
        headers={"X-Internal-Token": "dev-internal-token"},
    )
    assert res.status_code == 200
    rel = res.json()["related"]
    assert isinstance(rel, list)
    assert len(rel) <= 3
    assert "python" not in rel  # don't suggest self


async def test_related_deterministic(client):
    headers = {"X-Internal-Token": "dev-internal-token"}
    a = (await client.post("/related", json={"subreddit": "python"}, headers=headers)).json()
    b = (await client.post("/related", json={"subreddit": "python"}, headers=headers)).json()
    assert a == b


async def test_spam_check_flags_keyword(client):
    res = await client.post(
        "/spam-check",
        json={"body": "buy now! free money click here"},
        headers={"X-Internal-Token": "dev-internal-token"},
    )
    body = res.json()
    assert body["flagged"] is True
    assert body["reasons"]


async def test_spam_check_clean(client):
    res = await client.post(
        "/spam-check",
        json={"body": "Hello, this is a regular comment about Python."},
        headers={"X-Internal-Token": "dev-internal-token"},
    )
    body = res.json()
    assert body["flagged"] is False


async def test_spam_check_requires_internal_token(client):
    res = await client.post("/spam-check", json={"body": "hi"})
    assert res.status_code == 401
