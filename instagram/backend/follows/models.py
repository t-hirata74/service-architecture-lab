from django.conf import settings
from django.db import models


class Follow(models.Model):
    """ADR 0002: Adjacency List + 双方向 index。

    PK = (follower, followee) 複合で重複防止と following 列挙、
    secondary index (followee, follower) で followers 列挙を支える。
    """

    follower = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="following_edges",
    )
    followee = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="follower_edges",
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = "follow_edges"
        constraints = [
            models.UniqueConstraint(
                fields=("follower", "followee"), name="follow_edges_pk"
            ),
        ]
        indexes = [
            models.Index(
                fields=("followee", "follower"), name="follow_edges_reverse_idx"
            ),
            models.Index(fields=("followee", "created_at"), name="follow_edges_followee_at_idx"),
        ]
