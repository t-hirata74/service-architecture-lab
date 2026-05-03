"""ADR 0001: 「投稿者本人は同期 INSERT で即座に見える」UX を検証。

self entry は signal が同期で TimelineEntry を get_or_create する。
"""
import pytest

from posts.models import Post
from timeline.models import TimelineEntry


@pytest.mark.django_db
def test_self_entry_is_created_synchronously(alice):
    post = Post.objects.create(user=alice, caption="self")
    # signal で同期 INSERT 済み (Celery task 経由ではない)
    assert TimelineEntry.objects.filter(user=alice, post=post).exists()


@pytest.mark.django_db
def test_authed_post_create_via_view_appears_in_timeline_immediately(authed_client, alice):
    res = authed_client.post("/posts", {"caption": "via api"}, format="json")
    assert res.status_code == 201
    post_id = res.data["id"]
    timeline_res = authed_client.get("/timeline")
    assert timeline_res.status_code == 200
    ids = [item["id"] for item in timeline_res.data["results"]]
    assert post_id in ids
