async def _setup(client, username="alice", subname="python"):
    res = await client.post(
        "/auth/register", json={"username": username, "password": "secret123"}
    )
    token = res.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}
    await client.post("/r", json={"name": subname, "description": ""}, headers=headers)
    return headers


async def test_create_post_and_list(client):
    headers = await _setup(client)
    res = await client.post(
        "/r/python/posts",
        json={"title": "hello", "body": "world"},
        headers=headers,
    )
    assert res.status_code == 201, res.text
    body = res.json()
    assert body["title"] == "hello"
    # 新規投稿は 0 ではない初期 hot_score を持つ (ADR 0003)
    assert body["hot_score"] != 0.0

    # anonymous でも一覧が見える
    res = await client.get("/r/python/new")
    assert res.status_code == 200
    assert len(res.json()) == 1

    res = await client.get("/r/python/hot")
    assert res.status_code == 200
    assert len(res.json()) == 1


async def test_create_post_requires_auth(client):
    res = await client.post("/r/python/posts", json={"title": "x", "body": ""})
    assert res.status_code == 401


async def test_post_in_unknown_subreddit_404(client):
    headers = await _setup(client)
    res = await client.post(
        "/r/nonexistent/posts", json={"title": "x", "body": ""}, headers=headers
    )
    assert res.status_code == 404
