"""Django Admin 登録: `python manage.py createsuperuser` 後に
http://localhost:3050/admin/ でデータを確認できる。
"""
from django.contrib import admin
from django.contrib.auth.admin import UserAdmin

from .models import User


@admin.register(User)
class UserAdminCustom(UserAdmin):
    list_display = (
        "username",
        "email",
        "followers_count",
        "following_count",
        "posts_count",
        "is_staff",
    )
    fieldsets = UserAdmin.fieldsets + (
        (
            "Profile (instagram)",
            {"fields": ("bio", "followers_count", "following_count", "posts_count")},
        ),
    )
