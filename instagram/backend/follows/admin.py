from django.contrib import admin

from .models import Follow


@admin.register(Follow)
class FollowAdmin(admin.ModelAdmin):
    list_display = ("id", "follower", "followee", "created_at")
    raw_id_fields = ("follower", "followee")
    search_fields = ("follower__username", "followee__username")
