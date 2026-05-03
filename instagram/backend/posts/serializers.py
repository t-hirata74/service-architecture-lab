from rest_framework import serializers

from accounts.serializers import UserSerializer

from .models import Comment, Like, Post


class PostSerializer(serializers.ModelSerializer):
    """ADR 0003: list view では view 側で
    annotate(likes_count, comments_count) + Prefetch(liked_by_me) を済ませる前提。
    """

    user = UserSerializer(read_only=True)
    likes_count = serializers.IntegerField(read_only=True)
    comments_count = serializers.IntegerField(read_only=True)
    liked_by_me = serializers.SerializerMethodField()

    class Meta:
        model = Post
        fields = (
            "id",
            "user",
            "caption",
            "image_url",
            "created_at",
            "likes_count",
            "comments_count",
            "liked_by_me",
        )
        read_only_fields = ("id", "user", "created_at", "likes_count", "comments_count", "liked_by_me")

    def get_liked_by_me(self, obj: Post) -> bool:
        # ADR 0003: prefetch 必須。silent fallback は N+1 を隠す。
        if not hasattr(obj, "liked_by_me_list"):
            raise AssertionError(
                "Post.liked_by_me_list が prefetch されていない (ADR 0003)。"
                "list/detail view では posts.queries.posts_for_viewer() を使うこと。"
            )
        return bool(obj.liked_by_me_list)


class PostCreateSerializer(serializers.ModelSerializer):
    class Meta:
        model = Post
        fields = ("caption", "image_url")


class CommentSerializer(serializers.ModelSerializer):
    user = UserSerializer(read_only=True)

    class Meta:
        model = Comment
        fields = ("id", "user", "body", "created_at")
        read_only_fields = ("id", "user", "created_at")


class CommentCreateSerializer(serializers.ModelSerializer):
    class Meta:
        model = Comment
        fields = ("body",)


class LikeSerializer(serializers.ModelSerializer):
    user = UserSerializer(read_only=True)

    class Meta:
        model = Like
        fields = ("user", "created_at")
        read_only_fields = fields
