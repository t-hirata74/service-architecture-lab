from django.contrib import admin

from .models import Comment, Like, Post


@admin.register(Post)
class PostAdmin(admin.ModelAdmin):
    list_display = ("id", "user", "caption_short", "created_at", "deleted_at")
    list_filter = ("deleted_at",)
    search_fields = ("caption", "user__username")
    raw_id_fields = ("user",)

    def caption_short(self, obj: Post) -> str:
        return (obj.caption or "")[:40]


@admin.register(Like)
class LikeAdmin(admin.ModelAdmin):
    list_display = ("id", "post", "user", "created_at")
    raw_id_fields = ("post", "user")


@admin.register(Comment)
class CommentAdmin(admin.ModelAdmin):
    list_display = ("id", "post", "user", "body_short", "created_at")
    raw_id_fields = ("post", "user")

    def body_short(self, obj: Comment) -> str:
        return (obj.body or "")[:40]
