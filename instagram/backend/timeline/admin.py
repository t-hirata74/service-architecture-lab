from django.contrib import admin

from .models import TimelineEntry


@admin.register(TimelineEntry)
class TimelineEntryAdmin(admin.ModelAdmin):
    list_display = ("id", "user", "post", "created_at")
    raw_id_fields = ("user", "post")
    list_filter = ("created_at",)
