from django.contrib.auth import authenticate
from rest_framework import serializers

from .models import User


class RegisterSerializer(serializers.ModelSerializer):
    password = serializers.CharField(write_only=True, min_length=8)

    class Meta:
        model = User
        fields = ("username", "password", "bio")

    def create(self, validated_data: dict) -> User:
        password = validated_data.pop("password")
        user = User(**validated_data)
        user.set_password(password)
        user.save()
        return user


class LoginSerializer(serializers.Serializer):
    username = serializers.CharField()
    password = serializers.CharField(write_only=True)

    def validate(self, attrs: dict) -> dict:
        user = authenticate(username=attrs["username"], password=attrs["password"])
        if user is None:
            raise serializers.ValidationError("invalid credentials")
        attrs["user"] = user
        return attrs


class UserSerializer(serializers.ModelSerializer):
    """`is_followed_by_viewer` はコンテキストで明示的に要求された時だけ計算する。
    timeline の埋め込み user 等で毎件 follow 探索する N+1 を避けるため、
    `/users/<username>` の view だけが context に `include_follow_status=True` を渡す。
    """

    is_followed_by_viewer = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = (
            "id",
            "username",
            "bio",
            "followers_count",
            "following_count",
            "posts_count",
            "is_followed_by_viewer",
        )
        read_only_fields = fields

    def get_is_followed_by_viewer(self, obj: User) -> bool | None:
        if not self.context.get("include_follow_status"):
            return None
        request = self.context.get("request")
        if not request or not request.user.is_authenticated:
            return None
        if request.user.pk == obj.pk:
            return False
        from follows.models import Follow

        return Follow.objects.filter(follower=request.user, followee=obj).exists()
