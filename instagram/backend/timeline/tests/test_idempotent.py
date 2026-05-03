"""ADR 0001: Celery task の at-least-once 重複に対し UNIQUE 制約 +
ignore_conflicts で冪等性を保つ。
"""
import pytest

from follows.models import Follow
from posts.models import Post
from timeline.models import TimelineEntry
from timeline.tasks import (
    backfill_timeline_on_follow,
    fanout_post_to_followers,
)


@pytest.mark.django_db
def test_fanout_task_is_idempotent(alice, bob):
    Follow.objects.create(follower=bob, followee=alice)
    post = Post.objects.create(user=alice, caption="dup")
    # signal で 1 回 enqueue 済み (eager 実行)。手動でもう一度呼んでも重複しないこと。
    fanout_post_to_followers(post.pk)
    fanout_post_to_followers(post.pk)
    assert TimelineEntry.objects.filter(post=post, user=bob).count() == 1


@pytest.mark.django_db
def test_backfill_task_is_idempotent(alice, bob):
    Post.objects.create(user=alice, caption="p1")
    Post.objects.create(user=alice, caption="p2")
    backfill_timeline_on_follow(bob.pk, alice.pk)
    backfill_timeline_on_follow(bob.pk, alice.pk)
    # bob の timeline には alice の post が 2 件だけ (重複していない)
    assert TimelineEntry.objects.filter(user=bob).count() == 2


@pytest.mark.django_db
def test_fanout_skips_self_entry_to_avoid_double_insert(alice):
    """signal で self を同期 INSERT した後、follower 0 でも fan-out task が
    self を再 INSERT しないこと (UNIQUE で吸収はされるが、count を膨らませないこと)。"""
    post = Post.objects.create(user=alice, caption="self only")
    # post 作成で signal が self entry を作成 + fan-out task が enqueue (eager)
    # follower 0 なので fan-out は何もしない
    assert TimelineEntry.objects.filter(post=post).count() == 1
