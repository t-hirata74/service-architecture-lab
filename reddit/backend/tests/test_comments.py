"""ADR 0001 — Adjacency List + Materialized Path のテスト。

- path は `<10桁>` または `<10桁>/<10桁>/...` 形式 = lexicographic 順 = preorder
- subtree は `WHERE path LIKE 'prefix/%'` で取れる
- soft delete: 親を消しても子は残り取得可能 (Reddit と同じ「[deleted]」運用)
"""


async def _setup(client, username="alice"):
    res = await client.post(
        "/auth/register", json={"username": username, "password": "secret123"}
    )
    token = res.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}
    if username == "alice":
        await client.post("/r", json={"name": "python", "description": ""}, headers=headers)
        res = await client.post(
            "/r/python/posts", json={"title": "t", "body": ""}, headers=headers
        )
        return headers, res.json()["id"]
    return headers, None


async def _comment(client, headers, post_id, body, parent_id=None):
    payload = {"body": body}
    if parent_id is not None:
        payload["parent_id"] = parent_id
    res = await client.post(
        f"/posts/{post_id}/comments", json=payload, headers=headers
    )
    assert res.status_code == 201, res.text
    return res.json()


async def test_top_level_comment_path_and_depth(client):
    headers, post_id = await _setup(client)
    c = await _comment(client, headers, post_id, "hi")
    assert c["depth"] == 1
    assert c["path"] == f"{c['id']:010d}"
    assert c["parent_id"] is None


async def test_reply_chains_path_and_depth(client):
    headers, post_id = await _setup(client)
    root = await _comment(client, headers, post_id, "root")
    child = await _comment(client, headers, post_id, "child", parent_id=root["id"])
    grand = await _comment(client, headers, post_id, "grand", parent_id=child["id"])

    assert child["depth"] == 2
    assert child["path"] == f"{root['path']}/{child['id']:010d}"
    assert grand["depth"] == 3
    assert grand["path"].startswith(child["path"] + "/")


async def test_list_returns_preorder_by_path(client):
    headers, post_id = await _setup(client)
    a = await _comment(client, headers, post_id, "a")
    a1 = await _comment(client, headers, post_id, "a1", parent_id=a["id"])
    b = await _comment(client, headers, post_id, "b")
    a1a = await _comment(client, headers, post_id, "a1a", parent_id=a1["id"])

    res = await client.get(f"/posts/{post_id}/comments")
    assert res.status_code == 200
    bodies = [c["body"] for c in res.json()]
    # path 順は preorder DFS: a → a1 → a1a → b
    assert bodies == ["a", "a1", "a1a", "b"]


async def test_subtree_query_via_path_prefix(client):
    """path prefix がサブツリー判定として機能する."""
    headers, post_id = await _setup(client)
    a = await _comment(client, headers, post_id, "a")
    a1 = await _comment(client, headers, post_id, "a1", parent_id=a["id"])
    await _comment(client, headers, post_id, "b")

    res = await client.get(f"/posts/{post_id}/comments")
    rows = res.json()
    subtree = [c for c in rows if c["path"].startswith(a["path"] + "/")]
    assert len(subtree) == 1
    assert subtree[0]["id"] == a1["id"]


async def test_parent_must_belong_to_same_post(client):
    headers, post_id = await _setup(client)
    # 別 post を作成
    res = await client.post(
        "/r/python/posts", json={"title": "t2", "body": ""}, headers=headers
    )
    other_post_id = res.json()["id"]

    root = await _comment(client, headers, post_id, "root")
    res = await client.post(
        f"/posts/{other_post_id}/comments",
        json={"body": "wrong", "parent_id": root["id"]},
        headers=headers,
    )
    assert res.status_code == 400


async def test_unknown_parent_404(client):
    headers, post_id = await _setup(client)
    res = await client.post(
        f"/posts/{post_id}/comments",
        json={"body": "x", "parent_id": 999},
        headers=headers,
    )
    assert res.status_code == 404


async def test_soft_delete_keeps_children(client):
    headers, post_id = await _setup(client)
    root = await _comment(client, headers, post_id, "root")
    child = await _comment(client, headers, post_id, "child", parent_id=root["id"])

    res = await client.delete(f"/comments/{root['id']}", headers=headers)
    assert res.status_code == 200
    assert res.json()["deleted_at"] is not None

    # 子は残り、親も deleted_at 付きで返る
    res = await client.get(f"/posts/{post_id}/comments")
    rows = res.json()
    assert len(rows) == 2
    deleted_root = next(c for c in rows if c["id"] == root["id"])
    assert deleted_root["deleted_at"] is not None
    surviving_child = next(c for c in rows if c["id"] == child["id"])
    assert surviving_child["deleted_at"] is None


async def test_delete_requires_author(client):
    headers_a, post_id = await _setup(client, "alice")
    headers_b, _ = await _setup(client, "bob")
    c = await _comment(client, headers_a, post_id, "mine")
    res = await client.delete(f"/comments/{c['id']}", headers=headers_b)
    assert res.status_code == 403


async def test_create_requires_auth(client):
    headers, post_id = await _setup(client)
    res = await client.post(
        f"/posts/{post_id}/comments", json={"body": "anon"}
    )
    assert res.status_code == 401


async def test_comment_vote_independent_score(client):
    headers, post_id = await _setup(client)
    c = await _comment(client, headers, post_id, "x")

    res = await client.post(
        f"/comments/{c['id']}/vote", json={"value": 1}, headers=headers
    )
    assert res.status_code == 200
    assert res.json()["score"] == 1

    # comment vote は post.score に影響しない
    res = await client.get(f"/posts/{post_id}")
    assert res.json()["score"] == 0


async def test_comment_vote_404(client):
    headers, _ = await _setup(client)
    res = await client.post(
        "/comments/9999/vote", json={"value": 1}, headers=headers
    )
    assert res.status_code == 404
