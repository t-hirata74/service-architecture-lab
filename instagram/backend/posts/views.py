from django.db import IntegrityError, transaction
from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.decorators import api_view
from rest_framework.pagination import CursorPagination
from rest_framework.request import Request
from rest_framework.response import Response

from .models import Comment, Like, Post
from .queries import posts_for_viewer
from .serializers import (
    CommentCreateSerializer,
    CommentSerializer,
    PostCreateSerializer,
    PostSerializer,
)


class PostCursorPagination(CursorPagination):
    ordering = "-created_at"
    page_size = 20


class CommentCursorPagination(CursorPagination):
    ordering = "created_at"
    page_size = 20


@api_view(["POST", "GET"])
def post_list_create(request: Request) -> Response:
    if request.method == "POST":
        serializer = PostCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        post = serializer.save(user=request.user)
        # 単発の作成戻りは annotate を再実行せず手で詰める (1 query 増やすのを避ける)。
        post.likes_count = 0
        post.comments_count = 0
        post.liked_by_me_list = []
        return Response(PostSerializer(post).data, status=status.HTTP_201_CREATED)

    qs = posts_for_viewer(request.user)
    paginator = PostCursorPagination()
    page = paginator.paginate_queryset(qs, request)
    return paginator.get_paginated_response(PostSerializer(page, many=True).data)


@api_view(["GET", "DELETE"])
def post_detail(request: Request, pk: int) -> Response:
    if request.method == "GET":
        qs = posts_for_viewer(request.user)
        post = get_object_or_404(qs, pk=pk)
        return Response(PostSerializer(post).data)

    post = get_object_or_404(Post, pk=pk, deleted_at__isnull=True)
    if post.user_id != request.user.pk:
        return Response({"detail": "forbidden"}, status=status.HTTP_403_FORBIDDEN)

    # ADR 0001: soft delete + Celery で timeline_entries を遅延削除する。
    post.soft_delete()
    from timeline.tasks import remove_post_from_timelines

    pk_ = post.pk
    transaction.on_commit(lambda: remove_post_from_timelines.delay(pk_))
    return Response(status=status.HTTP_204_NO_CONTENT)


@api_view(["GET"])
def user_posts(request: Request, username: str) -> Response:
    qs = posts_for_viewer(request.user).filter(user__username=username)
    paginator = PostCursorPagination()
    page = paginator.paginate_queryset(qs, request)
    return paginator.get_paginated_response(PostSerializer(page, many=True).data)


@api_view(["POST", "DELETE"])
def like(request: Request, pk: int) -> Response:
    post = get_object_or_404(Post, pk=pk, deleted_at__isnull=True)
    if request.method == "POST":
        try:
            Like.objects.create(post=post, user=request.user)
        except IntegrityError:
            return Response({"detail": "already liked"}, status=status.HTTP_409_CONFLICT)
        return Response(status=status.HTTP_201_CREATED)

    deleted, _ = Like.objects.filter(post=post, user=request.user).delete()
    if deleted == 0:
        return Response({"detail": "not liked"}, status=status.HTTP_404_NOT_FOUND)
    return Response(status=status.HTTP_204_NO_CONTENT)


@api_view(["GET", "POST"])
def comment_list_create(request: Request, pk: int) -> Response:
    post = get_object_or_404(Post, pk=pk, deleted_at__isnull=True)
    if request.method == "POST":
        serializer = CommentCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        comment = serializer.save(post=post, user=request.user)
        return Response(CommentSerializer(comment).data, status=status.HTTP_201_CREATED)

    qs = (
        Comment.objects.filter(post=post)
        .select_related("user")
        .order_by("created_at")
    )
    paginator = CommentCursorPagination()
    page = paginator.paginate_queryset(qs, request)
    return paginator.get_paginated_response(CommentSerializer(page, many=True).data)
