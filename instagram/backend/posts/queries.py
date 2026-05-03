"""ADR 0003: list/detail view 用の N+1-safe queryset を 1 箇所に集約する。

「prefetch を View で書き散らさない」ための置き場所。timeline app も
ここを再利用することで「Post を返す全 view で `liked_by_me` が必ず prefetch
される」不変条件を維持する。
"""
from __future__ import annotations

from typing import Iterable

from django.db.models import Count, Prefetch, QuerySet

from .models import Like, Post


def _alive_with_counts(viewer) -> QuerySet[Post]:
    return (
        Post.objects.filter(deleted_at__isnull=True)
        .select_related("user")
        .annotate(
            likes_count=Count("likes", distinct=True),
            comments_count=Count("comments", distinct=True),
        )
        .prefetch_related(
            Prefetch(
                "likes",
                queryset=Like.objects.filter(user=viewer),
                to_attr="liked_by_me_list",
            )
        )
    )


def posts_for_viewer(viewer) -> QuerySet[Post]:
    """list view 用 (paginate 後にそのまま serializer に渡せる)。"""
    return _alive_with_counts(viewer)


def posts_by_ids_in_order(post_ids: Iterable[int], viewer) -> list[Post]:
    """timeline view 用: post_id 配列の順序を保ったまま hydrate。
    deleted_at が立った post は結果から落とす (soft delete の伝播待ちを許容)。
    """
    post_ids = list(post_ids)
    if not post_ids:
        return []
    qs = _alive_with_counts(viewer).filter(pk__in=post_ids)
    by_id = {p.pk: p for p in qs}
    return [by_id[pid] for pid in post_ids if pid in by_id]
