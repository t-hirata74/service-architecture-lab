"""GET /timeline の動作検証。

- フォロー中ユーザの post が見える
- フォローしていないユーザの post は見えない
- 時系列降順 (created_at desc)
- soft delete された post は除外される
"""
import time

import pytest

from follows.models import Follow
from posts.models import Post


@pytest.mark.django_db
def test_timeline_contains_followed_user_posts(authed_client, alice, bob):
    Follow.objects.create(follower=alice, followee=bob)
    p_bob = Post.objects.create(user=bob, caption="bob's")
    p_self = Post.objects.create(user=alice, caption="alice's")

    res = authed_client.get("/timeline")
    assert res.status_code == 200
    ids = [item["id"] for item in res.data["results"]]
    # 自分の投稿 + フォロー中の投稿が両方見える
    assert p_bob.pk in ids
    assert p_self.pk in ids


@pytest.mark.django_db
def test_timeline_excludes_unfollowed_user_posts(authed_client, alice, bob):
    # bob を follow せずに bob が投稿しても alice の timeline には現れない
    Post.objects.create(user=bob, caption="bob's lonely")
    res = authed_client.get("/timeline")
    assert res.status_code == 200
    assert res.data["results"] == []


@pytest.mark.django_db
def test_timeline_is_chronological_descending(authed_client, alice, bob):
    Follow.objects.create(follower=alice, followee=bob)
    p1 = Post.objects.create(user=bob, caption="first")
    time.sleep(0.01)  # auto_now_add の精度を分けるため
    p2 = Post.objects.create(user=bob, caption="second")
    time.sleep(0.01)
    p3 = Post.objects.create(user=alice, caption="third (self)")

    res = authed_client.get("/timeline")
    ids = [item["id"] for item in res.data["results"]]
    # 新しい順
    assert ids[: len(ids)] == [p3.pk, p2.pk, p1.pk] or ids == [p3.pk, p2.pk, p1.pk]


@pytest.mark.django_db
def test_timeline_excludes_soft_deleted_posts(authed_client, alice, bob):
    Follow.objects.create(follower=alice, followee=bob)
    p_visible = Post.objects.create(user=bob, caption="visible")
    p_deleted = Post.objects.create(user=bob, caption="will delete")
    p_deleted.soft_delete()

    res = authed_client.get("/timeline")
    ids = [item["id"] for item in res.data["results"]]
    assert p_visible.pk in ids
    assert p_deleted.pk not in ids
