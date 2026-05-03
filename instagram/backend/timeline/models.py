from django.conf import settings
from django.db import models

from posts.models import Post


class TimelineEntry(models.Model):
    """ADR 0001: fan-out on write の事前展開先。

    - UNIQUE (user, post) で fan-out task の at-least-once 重複を吸収
    - (user, -created_at) index で read を index scan に落とす
    - created_at は Post.created_at をコピー (backfill 経由でも時系列を保つ)
    """

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="timeline_entries",
    )
    post = models.ForeignKey(
        Post,
        on_delete=models.CASCADE,
        related_name="timeline_entries",
    )
    created_at = models.DateTimeField()

    class Meta:
        db_table = "timeline_entries"
        constraints = [
            models.UniqueConstraint(
                fields=("user", "post"), name="timeline_entries_user_post_uniq"
            ),
        ]
        indexes = [
            models.Index(
                fields=("user", "-created_at"), name="timeline_entries_user_at_idx"
            ),
        ]
