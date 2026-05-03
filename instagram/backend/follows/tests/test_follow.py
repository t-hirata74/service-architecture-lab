"""ADR 0002: follow / unfollow + counter ± 1 + UNIQUE 重複防止"""
import pytest

from accounts.models import User
from follows.models import Follow


@pytest.mark.django_db
def test_follow_creates_edge_and_increments_counters(authed_client, alice, bob):
    res = authed_client.post(f"/users/{bob.username}/follow")
    assert res.status_code == 201
    assert Follow.objects.filter(follower=alice, followee=bob).exists()
    alice.refresh_from_db()
    bob.refresh_from_db()
    assert alice.following_count == 1
    assert bob.followers_count == 1


@pytest.mark.django_db
def test_unfollow_decrements_counters(authed_client, alice, bob):
    Follow.objects.create(follower=alice, followee=bob)
    alice.following_count = 1
    bob.followers_count = 1
    alice.save()
    bob.save()

    res = authed_client.delete(f"/users/{bob.username}/follow")
    assert res.status_code == 204
    alice.refresh_from_db()
    bob.refresh_from_db()
    assert alice.following_count == 0
    assert bob.followers_count == 0


@pytest.mark.django_db
def test_duplicate_follow_returns_409(authed_client, alice, bob):
    authed_client.post(f"/users/{bob.username}/follow")
    res = authed_client.post(f"/users/{bob.username}/follow")
    assert res.status_code == 409


@pytest.mark.django_db
def test_cannot_follow_self(authed_client, alice):
    res = authed_client.post(f"/users/{alice.username}/follow")
    assert res.status_code == 400


@pytest.mark.django_db
def test_unfollow_when_not_following_returns_404(authed_client, alice, bob):
    res = authed_client.delete(f"/users/{bob.username}/follow")
    assert res.status_code == 404
