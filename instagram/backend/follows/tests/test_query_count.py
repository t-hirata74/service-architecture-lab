"""ADR 0003: followers / following 列挙の query 件数を固定する。

期待件数の内訳 (page_size=20):
- 1: target user lookup (`get_object_or_404 User`)
- 1: count (CursorPagination が次ページ判定に使う) — 実際は LIMIT+1 で count を回避するので 0
- 1: SELECT follow_edges JOIN users (select_related)
- 1: auth (token validation) ← APIClient.credentials は session に乗らないので毎リクエスト引く
合計 ~3-4。固定値で書くが、Django/DRF のバージョン差で揺れる場合は範囲で書く。
"""
import pytest
from django.test.utils import CaptureQueriesContext
from django.db import connection

from accounts.models import User
from follows.models import Follow


def _seed_followers(target: User, n: int, prefix: str = "u") -> None:
    """target を n 人がフォローしている状態を作る (prefix で命名衝突を回避)。"""
    followers = [
        User.objects.create_user(username=f"{prefix}{i}", password="x12345678!") for i in range(n)
    ]
    Follow.objects.bulk_create([Follow(follower=u, followee=target) for u in followers])


@pytest.mark.django_db
def test_followers_query_count_is_constant(authed_client, alice, bob):
    """N=5 と N=20 で同じ query 件数になることを確認 (ADR 0003 の "N に依存しない")。"""
    _seed_followers(bob, 5, prefix="a")
    with CaptureQueriesContext(connection) as ctx_5:
        res = authed_client.get(f"/users/{bob.username}/followers")
    assert res.status_code == 200
    count_5 = len(ctx_5.captured_queries)

    _seed_followers(bob, 15, prefix="b")
    with CaptureQueriesContext(connection) as ctx_20:
        res = authed_client.get(f"/users/{bob.username}/followers")
    assert res.status_code == 200
    count_20 = len(ctx_20.captured_queries)

    assert count_5 == count_20, (
        f"query count must not depend on N; got {count_5} for N=5, {count_20} for N=20"
    )


@pytest.mark.django_db
def test_following_query_count_is_constant(authed_client, alice):
    """alice が n 人をフォローしている状態で /following を引く。"""
    targets_5 = [User.objects.create_user(username=f"t{i}", password="x12345678!") for i in range(5)]
    Follow.objects.bulk_create([Follow(follower=alice, followee=t) for t in targets_5])
    with CaptureQueriesContext(connection) as ctx_5:
        res = authed_client.get(f"/users/{alice.username}/following")
    assert res.status_code == 200
    count_5 = len(ctx_5.captured_queries)

    targets_more = [User.objects.create_user(username=f"t{i + 5}", password="x12345678!") for i in range(15)]
    Follow.objects.bulk_create([Follow(follower=alice, followee=t) for t in targets_more])
    with CaptureQueriesContext(connection) as ctx_20:
        res = authed_client.get(f"/users/{alice.username}/following")
    assert res.status_code == 200
    count_20 = len(ctx_20.captured_queries)

    assert count_5 == count_20
