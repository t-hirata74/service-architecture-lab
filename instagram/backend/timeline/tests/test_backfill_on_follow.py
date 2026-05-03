"""ADR 0001: 新規 follow 時に followee の直近 N 件が follower の timeline に
入ることを検証。
"""
import pytest

from follows.models import Follow
from posts.models import Post
from timeline.models import TimelineEntry
from timeline.tasks import BACKFILL_LIMIT


@pytest.mark.django_db
def test_follow_backfills_recent_posts(alice, bob):
    # bob が 5 件投稿 (この時点では alice の timeline は空)
    posts = [Post.objects.create(user=bob, caption=f"p{i}") for i in range(5)]
    assert TimelineEntry.objects.filter(user=alice).count() == 0

    Follow.objects.create(follower=alice, followee=bob)

    # backfill task が同期で走り、alice の timeline に 5 件入る
    user_entries = TimelineEntry.objects.filter(user=alice)
    assert user_entries.count() == 5
    assert set(user_entries.values_list("post_id", flat=True)) == {p.pk for p in posts}


@pytest.mark.django_db
def test_follow_backfill_limited_to_recent_n(alice, bob):
    """BACKFILL_LIMIT を超える場合は新しい N 件だけ。"""
    n_total = BACKFILL_LIMIT + 5
    [Post.objects.create(user=bob, caption=f"p{i}") for i in range(n_total)]
    Follow.objects.create(follower=alice, followee=bob)
    assert TimelineEntry.objects.filter(user=alice).count() == BACKFILL_LIMIT


@pytest.mark.django_db
def test_unfollow_removes_user_posts_from_timeline(alice, bob):
    Post.objects.create(user=bob, caption="p1")
    Post.objects.create(user=bob, caption="p2")
    follow = Follow.objects.create(follower=alice, followee=bob)
    assert TimelineEntry.objects.filter(user=alice).count() == 2

    follow.delete()

    assert TimelineEntry.objects.filter(user=alice).count() == 0
