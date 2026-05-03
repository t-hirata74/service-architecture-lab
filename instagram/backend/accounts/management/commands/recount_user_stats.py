"""ADR 0002 / 0003: signal が落ちて denormalized counter がずれた場合の修復。

`User.followers_count / following_count / posts_count` を真値 (follow_edges /
posts) から再計算して書き戻す。夜間 batch で回す想定。
"""
from __future__ import annotations

from django.core.management.base import BaseCommand
from django.db import transaction
from django.db.models import Count, Q

from accounts.models import User


class Command(BaseCommand):
    help = "Recompute denormalized counters on User from follow_edges / posts."

    def add_arguments(self, parser) -> None:
        parser.add_argument(
            "--dry-run",
            action="store_true",
            help="差分を出力するだけで update しない",
        )

    def handle(self, *args, dry_run: bool = False, **options) -> None:
        # 1 query で 3 列の真値を取得 (Subquery でも書けるが、可読性優先で
        # annotate を使う)
        users = User.objects.annotate(
            true_followers=Count("follower_edges", distinct=True),
            true_following=Count("following_edges", distinct=True),
            true_posts=Count(
                "posts",
                filter=Q(posts__deleted_at__isnull=True),
                distinct=True,
            ),
        )

        drift = 0
        with transaction.atomic():
            for u in users:
                changes = {}
                if u.followers_count != u.true_followers:
                    changes["followers_count"] = u.true_followers
                if u.following_count != u.true_following:
                    changes["following_count"] = u.true_following
                if u.posts_count != u.true_posts:
                    changes["posts_count"] = u.true_posts
                if not changes:
                    continue
                drift += 1
                self.stdout.write(
                    f"@{u.username}: {dict((k, (getattr(u, k), v)) for k, v in changes.items())}"
                )
                if not dry_run:
                    User.objects.filter(pk=u.pk).update(**changes)

        verb = "would fix" if dry_run else "fixed"
        self.stdout.write(self.style.SUCCESS(f"{verb} {drift} user(s)"))
