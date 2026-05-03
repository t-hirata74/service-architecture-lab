"""ADR 0003: GET /timeline の query 件数が N に依存しないことを CI で固定。"""
import pytest
from django.db import connection
from django.test.utils import CaptureQueriesContext

from accounts.models import User
from follows.models import Follow
from posts.models import Like, Post


@pytest.mark.django_db
def test_timeline_query_count_is_constant(authed_client, alice):
    # alice が 1 人をフォローし、その人が n 件投稿する形
    bob = User.objects.create_user(username="bob", password="x12345678!")
    Follow.objects.create(follower=alice, followee=bob)

    # N=5
    for i in range(5):
        p = Post.objects.create(user=bob, caption=f"p{i}")
        Like.objects.create(post=p, user=alice)
    with CaptureQueriesContext(connection) as ctx_5:
        res = authed_client.get("/timeline")
    assert res.status_code == 200
    count_5 = len(ctx_5.captured_queries)

    # N=20 (新しく 15 件追加)
    for i in range(15):
        p = Post.objects.create(user=bob, caption=f"q{i}")
        Like.objects.create(post=p, user=alice)
    with CaptureQueriesContext(connection) as ctx_20:
        res = authed_client.get("/timeline")
    assert res.status_code == 200
    count_20 = len(ctx_20.captured_queries)

    assert count_5 == count_20, (
        f"timeline must not N+1; got {count_5} for N=5, {count_20} for N=20"
    )
