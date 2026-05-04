"""backend → ai-worker proxy + graceful degradation."""

import httpx
import respx


async def _setup_post(client, username="alice"):
    res = await client.post(
        "/auth/register", json={"username": username, "password": "secret123"}
    )
    headers = {"Authorization": f"Bearer {res.json()['access_token']}"}
    await client.post("/r", json={"name": "python", "description": ""}, headers=headers)
    res = await client.post(
        "/r/python/posts",
        json={"title": "FastAPI tutorial", "body": "python python fastapi async"},
        headers=headers,
    )
    return res.json()["id"]


@respx.mock
async def test_summarize_proxies_to_ai_worker(client):
    post_id = await _setup_post(client)
    respx.post("http://127.0.0.1:8060/summarize").mock(
        return_value=httpx.Response(
            200, json={"summary": "TL;DR: FastAPI tutorial", "keywords": ["fastapi", "python"]}
        )
    )
    res = await client.post(f"/posts/{post_id}/summarize")
    assert res.status_code == 200
    body = res.json()
    assert body["summary"].startswith("TL;DR")
    assert body["degraded"] is False


@respx.mock
async def test_summarize_degraded_on_unreachable(client):
    post_id = await _setup_post(client)
    respx.post("http://127.0.0.1:8060/summarize").mock(
        side_effect=httpx.ConnectError("connection refused")
    )
    res = await client.post(f"/posts/{post_id}/summarize")
    assert res.status_code == 200
    body = res.json()
    assert body["degraded"] is True
    assert body["reason"] == "unreachable"


@respx.mock
async def test_summarize_degraded_on_5xx(client):
    post_id = await _setup_post(client)
    respx.post("http://127.0.0.1:8060/summarize").mock(
        return_value=httpx.Response(503, text="Service Unavailable")
    )
    res = await client.post(f"/posts/{post_id}/summarize")
    body = res.json()
    assert body["degraded"] is True
    assert body["reason"] == "upstream_503"


async def test_summarize_404_for_unknown_post(client):
    # ai-worker は呼ばれない (404 で短絡)
    res = await client.post("/posts/9999/summarize")
    assert res.status_code == 404
