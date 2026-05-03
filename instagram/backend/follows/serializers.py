from rest_framework import serializers

from accounts.serializers import UserSerializer

from .models import Follow


class FollowSerializer(serializers.ModelSerializer):
    follower = UserSerializer(read_only=True)
    followee = UserSerializer(read_only=True)

    class Meta:
        model = Follow
        fields = ("follower", "followee", "created_at")
        read_only_fields = fields
