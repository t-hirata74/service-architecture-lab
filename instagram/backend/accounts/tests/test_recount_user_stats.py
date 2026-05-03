"""ADR 0002 派生: `manage.py recount_user_stats` で counter drift を修復できる。"""
from io import StringIO

import pytest
from django.core.management import call_command

from accounts.models import User
from follows.models import Follow
from posts.models import Post


@pytest.mark.django_db
def test_recount_fixes_drifted_counters(alice, bob):
    Follow.objects.create(follower=alice, followee=bob)
    Post.objects.create(user=alice, caption="hi")
    # signal が正しく動いた状態
    alice.refresh_from_db()
    bob.refresh_from_db()
    assert alice.following_count == 1
    assert alice.posts_count == 1
    assert bob.followers_count == 1

    # 直接 SQL で counter を狂わせる (signal が落ちたシナリオ)
    User.objects.filter(pk=alice.pk).update(
        followers_count=99, following_count=0, posts_count=0
    )
    User.objects.filter(pk=bob.pk).update(followers_count=0)

    out = StringIO()
    call_command("recount_user_stats", stdout=out)
    assert "fixed 2 user(s)" in out.getvalue()

    alice.refresh_from_db()
    bob.refresh_from_db()
    assert alice.followers_count == 0
    assert alice.following_count == 1
    assert alice.posts_count == 1
    assert bob.followers_count == 1


@pytest.mark.django_db
def test_recount_dry_run_does_not_modify(alice):
    User.objects.filter(pk=alice.pk).update(posts_count=42)
    out = StringIO()
    call_command("recount_user_stats", "--dry-run", stdout=out)
    assert "would fix 1 user(s)" in out.getvalue()
    alice.refresh_from_db()
    assert alice.posts_count == 42  # 変わっていない


@pytest.mark.django_db
def test_recount_excludes_soft_deleted_posts(alice):
    Post.objects.create(user=alice, caption="alive")
    p = Post.objects.create(user=alice, caption="dead")
    p.soft_delete()
    # soft_delete が posts_count を 1 → 元値 + 1 に戻している
    alice.refresh_from_db()
    assert alice.posts_count == 1

    # わざと狂わせて recount で真値に戻す
    User.objects.filter(pk=alice.pk).update(posts_count=99)
    out = StringIO()
    call_command("recount_user_stats", stdout=out)
    alice.refresh_from_db()
    assert alice.posts_count == 1  # alive のみ counted
