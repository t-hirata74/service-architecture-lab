"""posts_count を denormalize 更新する。Post の論理削除 / 復活はスコープ外なので
post_save (created) と post_delete のみで対応。
"""
from django.db.models import F
from django.db.models.signals import post_delete, post_save
from django.dispatch import receiver

from accounts.models import User

from .models import Post


@receiver(post_save, sender=Post)
def increment_posts_count(sender, instance: Post, created: bool, **kwargs) -> None:
    if not created:
        return
    User.objects.filter(pk=instance.user_id).update(posts_count=F("posts_count") + 1)


@receiver(post_delete, sender=Post)
def decrement_posts_count(sender, instance: Post, **kwargs) -> None:
    User.objects.filter(pk=instance.user_id, posts_count__gt=0).update(
        posts_count=F("posts_count") - 1
    )
