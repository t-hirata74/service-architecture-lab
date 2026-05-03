"""ADR 0003: list view の query 件数が N (= page size) に依存しないことを CI で固定する。

`assertNumQueries` の固定値は環境差で揺れがちなので、本テストでは
**「N=5 と N=20 で件数が一致する」** という不変条件で書く。これが破れたら
prefetch / annotate の崩れを意味する。
"""
import pytest
from django.db import connection
from django.test.utils import CaptureQueriesContext

from accounts.models import User
from posts.models import Comment, Like, Post


def _seed_posts(author: User, n: int, liker: User | None = None) -> None:
    posts = [Post.objects.create(user=author, caption=f"p{i}") for i in range(n)]
    for p in posts:
        if liker is not None:
            Like.objects.create(post=p, user=liker)
        Comment.objects.create(post=p, user=author, body="c")


@pytest.mark.django_db
def test_post_list_query_count_is_constant(authed_client, alice, bob):
    _seed_posts(bob, 5, liker=alice)
    with CaptureQueriesContext(connection) as ctx_5:
        res = authed_client.get("/posts")
    assert res.status_code == 200
    count_5 = len(ctx_5.captured_queries)

    _seed_posts(bob, 15, liker=alice)
    with CaptureQueriesContext(connection) as ctx_20:
        res = authed_client.get("/posts")
    assert res.status_code == 200
    count_20 = len(ctx_20.captured_queries)

    assert count_5 == count_20, (
        f"post list must not N+1; got {count_5} for N=5, {count_20} for N=20"
    )


@pytest.mark.django_db
def test_user_posts_query_count_is_constant(authed_client, alice, bob):
    _seed_posts(bob, 5, liker=alice)
    with CaptureQueriesContext(connection) as ctx_5:
        res = authed_client.get(f"/users/{bob.username}/posts")
    assert res.status_code == 200
    count_5 = len(ctx_5.captured_queries)

    _seed_posts(bob, 15, liker=alice)
    with CaptureQueriesContext(connection) as ctx_20:
        res = authed_client.get(f"/users/{bob.username}/posts")
    assert res.status_code == 200
    count_20 = len(ctx_20.captured_queries)

    assert count_5 == count_20


@pytest.mark.django_db
def test_post_list_returns_correct_liked_by_me_per_post(authed_client, alice, bob):
    """prefetch_related(Prefetch(... user=alice)) が post 単位で正しく
    bind されているか — 簡易に bob の post に alice が like したものとしないものを
    混在させて返却を確認。
    """
    p1 = Post.objects.create(user=bob, caption="p1")
    p2 = Post.objects.create(user=bob, caption="p2")
    Like.objects.create(post=p1, user=alice)  # p1 だけいいね済み
    Like.objects.create(post=p2, user=bob)    # p2 は bob がいいねしているが alice ではない

    res = authed_client.get("/posts")
    assert res.status_code == 200
    by_id = {item["id"]: item for item in res.data["results"]}
    assert by_id[p1.id]["liked_by_me"] is True
    assert by_id[p2.id]["liked_by_me"] is False
