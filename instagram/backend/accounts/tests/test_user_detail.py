"""GET /users/<username> の `is_followed_by_viewer` 計算を検証。

context の include_follow_status フラグで挙動が分岐する設計なので、
- self を見たとき: False
- まだ follow していないとき: False
- follow 中: True
- それ以外の経路 (例: PostSerializer.user 埋め込み): null
"""
import pytest

from follows.models import Follow
from posts.models import Post


@pytest.mark.django_db
def test_self_profile_is_followed_by_viewer_is_false(authed_client, alice):
    res = authed_client.get(f"/users/{alice.username}")
    assert res.status_code == 200
    assert res.data["is_followed_by_viewer"] is False


@pytest.mark.django_db
def test_unfollowed_profile_is_followed_by_viewer_is_false(authed_client, alice, bob):
    res = authed_client.get(f"/users/{bob.username}")
    assert res.status_code == 200
    assert res.data["is_followed_by_viewer"] is False


@pytest.mark.django_db
def test_followed_profile_is_followed_by_viewer_is_true(authed_client, alice, bob):
    Follow.objects.create(follower=alice, followee=bob)
    res = authed_client.get(f"/users/{bob.username}")
    assert res.status_code == 200
    assert res.data["is_followed_by_viewer"] is True


@pytest.mark.django_db
def test_embedded_user_in_post_returns_null(authed_client, alice, bob):
    """PostSerializer は include_follow_status を渡さないので、埋め込み user の
    is_followed_by_viewer は常に null (= 計算スキップ)。"""
    Follow.objects.create(follower=alice, followee=bob)
    Post.objects.create(user=bob, caption="hi")
    res = authed_client.get("/posts")
    assert res.status_code == 200
    assert res.data["results"][0]["user"]["is_followed_by_viewer"] is None
