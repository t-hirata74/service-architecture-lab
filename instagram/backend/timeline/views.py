from rest_framework.decorators import api_view
from rest_framework.pagination import CursorPagination
from rest_framework.request import Request
from rest_framework.response import Response

from posts.queries import posts_by_ids_in_order
from posts.serializers import PostSerializer

from .models import TimelineEntry


class TimelineCursorPagination(CursorPagination):
    ordering = "-created_at"
    page_size = 20


@api_view(["GET"])
def timeline(request: Request) -> Response:
    """ADR 0001 + 0003: timeline_entries の index scan で post_id を取り、
    posts.queries で N+1-safe に hydrate する 2 段階クエリ。"""
    entry_qs = TimelineEntry.objects.filter(user=request.user).order_by("-created_at")
    paginator = TimelineCursorPagination()
    page = paginator.paginate_queryset(entry_qs, request)
    post_ids = [e.post_id for e in page]
    posts = posts_by_ids_in_order(post_ids, request.user)
    return paginator.get_paginated_response(PostSerializer(posts, many=True).data)
