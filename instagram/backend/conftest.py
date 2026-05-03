"""Shared fixtures for instagram backend tests."""
from __future__ import annotations

import pytest
from rest_framework.authtoken.models import Token
from rest_framework.test import APIClient

from accounts.models import User


@pytest.fixture
def api_client() -> APIClient:
    return APIClient()


@pytest.fixture
def make_user(db):
    def _make(username: str = "alice", password: str = "password123!") -> User:
        return User.objects.create_user(username=username, password=password)

    return _make


@pytest.fixture
def alice(make_user) -> User:
    return make_user("alice")


@pytest.fixture
def bob(make_user) -> User:
    return make_user("bob")


@pytest.fixture
def authed_client(api_client, alice) -> APIClient:
    token, _ = Token.objects.get_or_create(user=alice)
    api_client.credentials(HTTP_AUTHORIZATION=f"Token {token.key}")
    return api_client
