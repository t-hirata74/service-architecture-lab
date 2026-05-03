from django.contrib.auth.models import AbstractUser
from django.db import models


class User(AbstractUser):
    """ADR 0002: followers_count / following_count を denormalize して保持。
    更新は follows.signals が F('count') ± 1 で行う。
    """

    bio = models.CharField(max_length=200, blank=True, default="")
    followers_count = models.PositiveIntegerField(default=0)
    following_count = models.PositiveIntegerField(default=0)
    posts_count = models.PositiveIntegerField(default=0)

    class Meta:
        db_table = "users"

    def __str__(self) -> str:
        return self.username
