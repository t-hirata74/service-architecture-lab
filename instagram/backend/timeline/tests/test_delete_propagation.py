"""ADR 0001: Post の soft delete + 非同期 fan-out 削除で全 follower の timeline
から消えることを検証。
"""
import pytest

from follows.models import Follow
from posts.models import Post
from rest_framework.authtoken.models import Token
from timeline.models import TimelineEntry


@pytest.mark.django_db
def test_post_delete_via_view_removes_timeline_entries(api_client, alice, bob):
    """alice が bob を follow している状態で bob が投稿 → alice の timeline に出る →
    bob が DELETE → 全員の timeline から消える"""
    Follow.objects.create(follower=alice, followee=bob)
    post = Post.objects.create(user=bob, caption="will delete")
    assert TimelineEntry.objects.filter(post=post).count() == 2  # bob (self) + alice

    token, _ = Token.objects.get_or_create(user=bob)
    api_client.credentials(HTTP_AUTHORIZATION=f"Token {token.key}")
    res = api_client.delete(f"/posts/{post.pk}")
    assert res.status_code == 204

    # remove_post_from_timelines task が同期実行されて全 entry が消える
    assert TimelineEntry.objects.filter(post=post).count() == 0


@pytest.mark.django_db
def test_post_owner_check_before_delete(authed_client, alice, bob):
    """他人の post を消そうとしたら 403、timeline_entries は影響しない。"""
    Follow.objects.create(follower=alice, followee=bob)
    post = Post.objects.create(user=bob, caption="bob's")
    res = authed_client.delete(f"/posts/{post.pk}")
    assert res.status_code == 403
    assert TimelineEntry.objects.filter(post=post).count() == 2
