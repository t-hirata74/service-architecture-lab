import pytest

from posts.models import Comment, Like, Post


@pytest.mark.django_db
def test_create_post_increments_posts_count(authed_client, alice):
    res = authed_client.post(
        "/posts",
        {"caption": "hello", "image_url": "https://example.test/1.jpg"},
        format="json",
    )
    assert res.status_code == 201
    assert res.data["caption"] == "hello"
    assert res.data["likes_count"] == 0
    assert res.data["liked_by_me"] is False
    alice.refresh_from_db()
    assert alice.posts_count == 1


@pytest.mark.django_db
def test_post_detail_returns_counts(authed_client, alice, bob):
    post = Post.objects.create(user=alice, caption="hi")
    Like.objects.create(post=post, user=bob)
    Comment.objects.create(post=post, user=bob, body="nice")

    res = authed_client.get(f"/posts/{post.pk}")
    assert res.status_code == 200
    assert res.data["likes_count"] == 1
    assert res.data["comments_count"] == 1
    assert res.data["liked_by_me"] is False  # alice はいいねしていない


@pytest.mark.django_db
def test_liked_by_me_is_true_after_like(authed_client, alice):
    post = Post.objects.create(user=alice, caption="hi")
    Like.objects.create(post=post, user=alice)
    res = authed_client.get(f"/posts/{post.pk}")
    assert res.data["liked_by_me"] is True


@pytest.mark.django_db
def test_delete_post_only_by_owner(authed_client, alice, bob):
    post = Post.objects.create(user=bob, caption="bob's")
    res = authed_client.delete(f"/posts/{post.pk}")
    assert res.status_code == 403
    assert Post.objects.filter(pk=post.pk).exists()


@pytest.mark.django_db
def test_delete_post_decrements_count(authed_client, alice):
    alice.posts_count = 1
    alice.save()
    post = Post.objects.create(user=alice, caption="hi")
    # post_save で +1 されるので保存後は 2
    alice.refresh_from_db()
    assert alice.posts_count == 2

    res = authed_client.delete(f"/posts/{post.pk}")
    assert res.status_code == 204
    alice.refresh_from_db()
    assert alice.posts_count == 1


@pytest.mark.django_db
def test_like_idempotent(authed_client, alice):
    post = Post.objects.create(user=alice, caption="hi")
    res1 = authed_client.post(f"/posts/{post.pk}/like")
    assert res1.status_code == 201
    res2 = authed_client.post(f"/posts/{post.pk}/like")
    assert res2.status_code == 409


@pytest.mark.django_db
def test_unlike_returns_404_when_not_liked(authed_client, alice):
    post = Post.objects.create(user=alice, caption="hi")
    res = authed_client.delete(f"/posts/{post.pk}/like")
    assert res.status_code == 404


@pytest.mark.django_db
def test_create_comment(authed_client, alice):
    post = Post.objects.create(user=alice, caption="hi")
    res = authed_client.post(
        f"/posts/{post.pk}/comments", {"body": "first!"}, format="json"
    )
    assert res.status_code == 201
    assert res.data["body"] == "first!"
    assert res.data["user"]["username"] == "alice"
