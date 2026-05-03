"""ADR 0001: 4 つの非同期タスクで timeline_entries を維持する。

- fanout_post_to_followers : Post 作成時、follower 全員の timeline に挿入
- remove_post_from_timelines : Post soft delete 時、該当 entry を一括削除
- backfill_timeline_on_follow : 新規 follow 時、followee の直近 N 件を follower の timeline に流し込む
- remove_user_posts_from_timeline : unfollow 時、followee の posts を follower の timeline から消す

すべて at-least-once。UNIQUE 制約 + ignore_conflicts で再実行を冪等化する。
"""
from __future__ import annotations

from celery import shared_task

from follows.models import Follow
from posts.models import Post

from .models import TimelineEntry

BACKFILL_LIMIT = 20


@shared_task
def fanout_post_to_followers(post_id: int) -> int:
    try:
        post = Post.objects.get(pk=post_id, deleted_at__isnull=True)
    except Post.DoesNotExist:
        return 0  # 既に削除されたら何もしない (race 許容)
    follower_ids = Follow.objects.filter(followee_id=post.user_id).values_list(
        "follower_id", flat=True
    )
    entries = [
        TimelineEntry(user_id=fid, post_id=post.pk, created_at=post.created_at)
        for fid in follower_ids
        if fid != post.user_id  # self entry は signal で同期 INSERT 済み
    ]
    if not entries:
        return 0
    TimelineEntry.objects.bulk_create(entries, ignore_conflicts=True)
    return len(entries)


@shared_task
def remove_post_from_timelines(post_id: int) -> int:
    deleted, _ = TimelineEntry.objects.filter(post_id=post_id).delete()
    return deleted


@shared_task
def backfill_timeline_on_follow(follower_id: int, followee_id: int) -> int:
    posts = list(
        Post.objects.filter(user_id=followee_id, deleted_at__isnull=True)
        .order_by("-created_at")[:BACKFILL_LIMIT]
    )
    entries = [
        TimelineEntry(user_id=follower_id, post_id=p.pk, created_at=p.created_at)
        for p in posts
    ]
    if not entries:
        return 0
    TimelineEntry.objects.bulk_create(entries, ignore_conflicts=True)
    return len(entries)


@shared_task
def remove_user_posts_from_timeline(follower_id: int, followee_id: int) -> int:
    deleted, _ = TimelineEntry.objects.filter(
        user_id=follower_id, post__user_id=followee_id
    ).delete()
    return deleted
