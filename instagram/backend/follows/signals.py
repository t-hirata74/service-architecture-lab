"""ADR 0002: counter は F('count') ± 1 で原子更新。signal 例外時の修復は
manage.py recount_follows (Phase 派生) で扱う。
"""
from django.db.models import F
from django.db.models.signals import post_delete, post_save
from django.dispatch import receiver

from accounts.models import User

from .models import Follow


@receiver(post_save, sender=Follow)
def increment_counters(sender, instance: Follow, created: bool, **kwargs) -> None:
    if not created:
        return
    User.objects.filter(pk=instance.follower_id).update(
        following_count=F("following_count") + 1
    )
    User.objects.filter(pk=instance.followee_id).update(
        followers_count=F("followers_count") + 1
    )


@receiver(post_delete, sender=Follow)
def decrement_counters(sender, instance: Follow, **kwargs) -> None:
    User.objects.filter(pk=instance.follower_id, following_count__gt=0).update(
        following_count=F("following_count") - 1
    )
    User.objects.filter(pk=instance.followee_id, followers_count__gt=0).update(
        followers_count=F("followers_count") - 1
    )
