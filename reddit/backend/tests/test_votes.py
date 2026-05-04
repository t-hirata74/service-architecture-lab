"""ADR 0002 — 投票整合性のテスト。

- 0 → +1 → -1 → 0 の遷移で score が +1, -2, +1 と相対加算される
- 同じ value で 2 回投票しても idempotent (delta = 0)
- 別ユーザの投票が独立に積算される
"""


async def _register(client, username):
    res = await client.post(
        "/auth/register", json={"username": username, "password": "secret123"}
    )
    return res.json()["access_token"]


async def _bootstrap_post(client):
    token_a = await _register(client, "alice")
    headers_a = {"Authorization": f"Bearer {token_a}"}
    await client.post("/r", json={"name": "python", "description": ""}, headers=headers_a)
    res = await client.post(
        "/r/python/posts", json={"title": "t", "body": ""}, headers=headers_a
    )
    post_id = res.json()["id"]
    return post_id, headers_a


async def test_vote_toggle_sequence(client):
    post_id, headers = await _bootstrap_post(client)

    # 0 → +1
    res = await client.post(f"/posts/{post_id}/vote", json={"value": 1}, headers=headers)
    assert res.status_code == 200
    assert res.json()["score"] == 1

    # +1 → -1 (delta = -2)
    res = await client.post(f"/posts/{post_id}/vote", json={"value": -1}, headers=headers)
    assert res.json()["score"] == -1

    # -1 → 0 (delta = +1)
    res = await client.post(f"/posts/{post_id}/vote", json={"value": 0}, headers=headers)
    assert res.json()["score"] == 0


async def test_vote_idempotent_same_value(client):
    post_id, headers = await _bootstrap_post(client)
    res = await client.post(f"/posts/{post_id}/vote", json={"value": 1}, headers=headers)
    assert res.json()["score"] == 1
    # 同じ値で 2 回目: delta=0 なので二重加算されない
    res = await client.post(f"/posts/{post_id}/vote", json={"value": 1}, headers=headers)
    assert res.json()["score"] == 1


async def test_vote_independent_per_user(client):
    post_id, headers_a = await _bootstrap_post(client)
    token_b = await _register(client, "bob")
    headers_b = {"Authorization": f"Bearer {token_b}"}

    await client.post(f"/posts/{post_id}/vote", json={"value": 1}, headers=headers_a)
    res = await client.post(f"/posts/{post_id}/vote", json={"value": 1}, headers=headers_b)
    assert res.json()["score"] == 2

    # bob だけ取り消し → score = 1
    res = await client.post(f"/posts/{post_id}/vote", json={"value": 0}, headers=headers_b)
    assert res.json()["score"] == 1


async def test_vote_requires_auth(client):
    res = await client.post("/posts/1/vote", json={"value": 1})
    assert res.status_code == 401


async def test_vote_target_not_found(client):
    token = await _register(client, "alice")
    headers = {"Authorization": f"Bearer {token}"}
    res = await client.post("/posts/9999/vote", json={"value": 1}, headers=headers)
    assert res.status_code == 404
