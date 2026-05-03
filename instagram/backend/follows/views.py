from django.db import IntegrityError
from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.decorators import api_view
from rest_framework.pagination import CursorPagination
from rest_framework.request import Request
from rest_framework.response import Response

from accounts.models import User
from accounts.serializers import UserSerializer

from .models import Follow


class FollowCursorPagination(CursorPagination):
    ordering = "-created_at"
    page_size = 20


@api_view(["POST", "DELETE"])
def follow(request: Request, username: str) -> Response:
    target = get_object_or_404(User, username=username)
    if target.pk == request.user.pk:
        return Response({"detail": "cannot follow yourself"}, status=status.HTTP_400_BAD_REQUEST)

    if request.method == "POST":
        try:
            Follow.objects.create(follower=request.user, followee=target)
        except IntegrityError:
            return Response({"detail": "already following"}, status=status.HTTP_409_CONFLICT)
        return Response(status=status.HTTP_201_CREATED)

    deleted, _ = Follow.objects.filter(follower=request.user, followee=target).delete()
    if deleted == 0:
        return Response({"detail": "not following"}, status=status.HTTP_404_NOT_FOUND)
    return Response(status=status.HTTP_204_NO_CONTENT)


@api_view(["GET"])
def followers(request: Request, username: str) -> Response:
    """ADR 0003: secondary index (followee, follower) を狙う。
    follower の User を select_related で 1 query に束ねる。
    """
    target = get_object_or_404(User, username=username)
    qs = (
        Follow.objects.filter(followee=target)
        .select_related("follower")
        .order_by("-created_at")
    )
    paginator = FollowCursorPagination()
    page = paginator.paginate_queryset(qs, request)
    data = UserSerializer([edge.follower for edge in page], many=True).data
    return paginator.get_paginated_response(data)


@api_view(["GET"])
def following(request: Request, username: str) -> Response:
    """ADR 0003: PK (follower, followee) を狙う。"""
    target = get_object_or_404(User, username=username)
    qs = (
        Follow.objects.filter(follower=target)
        .select_related("followee")
        .order_by("-created_at")
    )
    paginator = FollowCursorPagination()
    page = paginator.paginate_queryset(qs, request)
    data = UserSerializer([edge.followee for edge in page], many=True).data
    return paginator.get_paginated_response(data)
