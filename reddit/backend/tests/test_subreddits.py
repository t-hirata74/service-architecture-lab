async def _register(client, username):
    res = await client.post(
        "/auth/register", json={"username": username, "password": "secret123"}
    )
    return res.json()["access_token"]


async def test_create_subreddit_and_anonymous_read(client):
    token = await _register(client, "alice")
    res = await client.post(
        "/r",
        json={"name": "python", "description": "py community"},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert res.status_code == 201, res.text
    assert res.json()["name"] == "python"

    # anonymous list / detail
    res = await client.get("/r")
    assert res.status_code == 200
    assert any(s["name"] == "python" for s in res.json())

    res = await client.get("/r/python")
    assert res.status_code == 200


async def test_create_subreddit_requires_auth(client):
    res = await client.post("/r", json={"name": "go", "description": ""})
    assert res.status_code == 401


async def test_subscribe_toggle(client):
    token = await _register(client, "alice")
    headers = {"Authorization": f"Bearer {token}"}
    await client.post("/r", json={"name": "python", "description": ""}, headers=headers)

    # creator が auto-subscribe されているので、最初の toggle は unsubscribe
    res = await client.post("/r/python/subscribe", headers=headers)
    assert res.status_code == 200
    assert res.json() == {"subscribed": False}

    res = await client.post("/r/python/subscribe", headers=headers)
    assert res.json() == {"subscribed": True}


async def test_create_duplicate_name_409(client):
    token = await _register(client, "alice")
    headers = {"Authorization": f"Bearer {token}"}
    await client.post("/r", json={"name": "python", "description": ""}, headers=headers)
    res = await client.post("/r", json={"name": "python", "description": "x"}, headers=headers)
    assert res.status_code == 409
