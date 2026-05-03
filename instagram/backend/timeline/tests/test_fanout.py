"""ADR 0001: Post 作成時の fan-out 動作を検証。

CELERY_TASK_ALWAYS_EAGER=True (conftest.py) で task は同期実行される。
"""
import pytest

from posts.models import Post
from follows.models import Follow
from timeline.models import TimelineEntry


@pytest.mark.django_db
def test_post_creation_fans_out_to_followers(alice, bob, make_user):
    carol = make_user("carol")
    Follow.objects.create(follower=bob, followee=alice)
    Follow.objects.create(follower=carol, followee=alice)

    post = Post.objects.create(user=alice, caption="hi all")

    assert TimelineEntry.objects.filter(user=alice, post=post).exists(), "self entry"
    assert TimelineEntry.objects.filter(user=bob, post=post).exists()
    assert TimelineEntry.objects.filter(user=carol, post=post).exists()
    # 3 件 (self + 2 followers)
    assert TimelineEntry.objects.filter(post=post).count() == 3


@pytest.mark.django_db
def test_post_creation_with_no_followers_only_self(alice):
    post = Post.objects.create(user=alice, caption="lonely")
    entries = TimelineEntry.objects.filter(post=post)
    assert entries.count() == 1
    assert entries.first().user_id == alice.pk
