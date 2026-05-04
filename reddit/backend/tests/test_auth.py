async def register(client, username="alice", password="secret123"):
    res = await client.post(
        "/auth/register", json={"username": username, "password": password}
    )
    assert res.status_code == 201, res.text
    return res.json()


async def test_register_login_me(client):
    body = await register(client)
    token = body["access_token"]
    assert body["user"]["username"] == "alice"

    res = await client.get("/me", headers={"Authorization": f"Bearer {token}"})
    assert res.status_code == 200
    assert res.json()["username"] == "alice"


async def test_register_duplicate_username(client):
    await register(client, username="bob")
    res = await client.post("/auth/register", json={"username": "bob", "password": "secret123"})
    assert res.status_code == 409


async def test_login_wrong_password(client):
    await register(client, username="carol", password="secret123")
    res = await client.post("/auth/login", json={"username": "carol", "password": "WRONG"})
    assert res.status_code == 401


async def test_me_without_token(client):
    res = await client.get("/me")
    assert res.status_code == 401
