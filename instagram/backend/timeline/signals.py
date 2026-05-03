"""ADR 0001: timeline 関連の signal を timeline 側に集約する。

- Post 作成: 投稿者本人の self entry は同期 INSERT、follower への fan-out は async
- Follow 作成: 新フォロワーの timeline に followee の直近 N 件を backfill (async)
- Follow 削除: follower の timeline から followee の posts を一括削除 (async)

`transaction.on_commit` で Celery enqueue を transaction commit 後に遅らせる。
ATOMIC_REQUESTS=False の現状でも auto-commit ↔ on_commit が等価に動くので
将来 ATOMIC_REQUESTS を有効化しても安全。
"""
from __future__ import annotations

from django.db import transaction
from django.db.models.signals import post_delete, post_save
from django.dispatch import receiver

from follows.models import Follow
from posts.models import Post

from .models import TimelineEntry
from .tasks import (
    backfill_timeline_on_follow,
    fanout_post_to_followers,
    remove_user_posts_from_timeline,
)


@receiver(post_save, sender=Post)
def on_post_created(sender, instance: Post, created: bool, **kwargs) -> None:
    if not created:
        return
    # self entry: 投稿者は即座に自分の post を timeline で見られる (architecture.md)
    TimelineEntry.objects.get_or_create(
        user_id=instance.user_id,
        post_id=instance.pk,
        defaults={"created_at": instance.created_at},
    )
    pk = instance.pk
    transaction.on_commit(lambda: fanout_post_to_followers.delay(pk))


@receiver(post_save, sender=Follow)
def on_follow_created(sender, instance: Follow, created: bool, **kwargs) -> None:
    if not created:
        return
    fid, tid = instance.follower_id, instance.followee_id
    transaction.on_commit(lambda: backfill_timeline_on_follow.delay(fid, tid))


@receiver(post_delete, sender=Follow)
def on_follow_deleted(sender, instance: Follow, **kwargs) -> None:
    fid, tid = instance.follower_id, instance.followee_id
    transaction.on_commit(lambda: remove_user_posts_from_timeline.delay(fid, tid))
