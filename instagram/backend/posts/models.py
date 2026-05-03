from django.conf import settings
from django.db import models
from django.db.models import F
from django.utils import timezone


class Post(models.Model):
    """ADR 0003 Index 一覧: (user, created_at desc) と (created_at desc) を張る。"""

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="posts",
    )
    caption = models.TextField(blank=True, default="")
    image_url = models.CharField(max_length=500, blank=True, default="")
    created_at = models.DateTimeField(auto_now_add=True)
    deleted_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        db_table = "posts"
        indexes = [
            models.Index(fields=("user", "-created_at"), name="posts_user_created_idx"),
            models.Index(fields=("-created_at",), name="posts_created_idx"),
        ]

    def soft_delete(self) -> None:
        """ADR 0001: hard delete + CASCADE は非同期 fan-out 削除と競合するので
        soft delete + Celery で timeline_entries を遅延削除する経路を採る。
        view は本メソッドを呼ぶだけ。
        """
        if self.deleted_at is not None:
            return
        from accounts.models import User

        self.deleted_at = timezone.now()
        self.save(update_fields=["deleted_at"])
        User.objects.filter(pk=self.user_id, posts_count__gt=0).update(
            posts_count=F("posts_count") - 1
        )


class Like(models.Model):
    """ADR 0003 Index 一覧: UNIQUE(post, user) で重複防止 + 「自分がいいねしたか」prefetch source。"""

    post = models.ForeignKey(Post, on_delete=models.CASCADE, related_name="likes")
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="likes",
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = "likes"
        constraints = [
            models.UniqueConstraint(fields=("post", "user"), name="likes_pk"),
        ]


class Comment(models.Model):
    post = models.ForeignKey(Post, on_delete=models.CASCADE, related_name="comments")
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="comments",
    )
    body = models.TextField()
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = "comments"
        indexes = [
            models.Index(fields=("post", "created_at"), name="comments_post_created_idx"),
        ]
