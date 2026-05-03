"""GET /discover と POST /tags/suggest が ai-worker を呼び出して結果を返すことを検証。
ai-worker 自体は別プロセスなので requests を mock する。
"""
from __future__ import annotations

from unittest.mock import patch

import pytest

from posts.models import Post


class _FakeResp:
    def __init__(self, payload, status=200):
        self._payload = payload
        self.status_code = status

    def json(self):
        return self._payload

    def raise_for_status(self):
        if self.status_code >= 400:
            import requests

            raise requests.HTTPError("boom")


@pytest.mark.django_db
def test_discover_hydrates_post_ids_from_ai_worker(authed_client, alice, bob):
    p1 = Post.objects.create(user=bob, caption="b1")
    p2 = Post.objects.create(user=bob, caption="b2")
    fake = _FakeResp({"post_ids": [p2.pk, p1.pk]})
    with patch("posts.views.requests.post", return_value=fake) as m:
        res = authed_client.get("/discover")
    assert res.status_code == 200
    ids = [item["id"] for item in res.data["results"]]
    assert ids == [p2.pk, p1.pk]
    # ai-worker が呼ばれた URL に top_k と user_id が乗っていること
    call = m.call_args
    assert call.kwargs["json"]["user_id"] == alice.pk
    assert call.kwargs["json"]["top_k"] == 20


@pytest.mark.django_db
def test_discover_returns_empty_on_ai_worker_failure(authed_client, alice):
    import requests

    with patch("posts.views.requests.post", side_effect=requests.ConnectionError("down")):
        res = authed_client.get("/discover")
    assert res.status_code == 200
    assert res.data["results"] == []


@pytest.mark.django_db
def test_suggest_tags_proxies_ai_worker(authed_client):
    fake = _FakeResp({"tags": ["nature", "city"]})
    with patch("posts.views.requests.post", return_value=fake):
        res = authed_client.post(
            "/tags/suggest", {"image_url": "https://x.test/p.jpg"}, format="json"
        )
    assert res.status_code == 200
    assert res.data == {"tags": ["nature", "city"]}


@pytest.mark.django_db
def test_suggest_tags_validates_input(authed_client):
    res = authed_client.post("/tags/suggest", {}, format="json")
    assert res.status_code == 400
