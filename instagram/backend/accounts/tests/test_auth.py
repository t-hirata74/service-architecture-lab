"""ADR 0004: register → login → token で保護 endpoint 叩く / logout で無効化"""
import pytest
from rest_framework.authtoken.models import Token

from accounts.models import User


@pytest.mark.django_db
def test_register_returns_token_and_user(api_client):
    res = api_client.post(
        "/auth/register",
        {"username": "alice", "password": "password123!"},
        format="json",
    )
    assert res.status_code == 201
    assert "token" in res.data
    assert res.data["user"]["username"] == "alice"
    assert User.objects.filter(username="alice").exists()


@pytest.mark.django_db
def test_login_returns_token_for_existing_user(api_client, alice):
    res = api_client.post(
        "/auth/login",
        {"username": "alice", "password": "password123!"},
        format="json",
    )
    assert res.status_code == 200
    assert "token" in res.data


@pytest.mark.django_db
def test_login_rejects_wrong_password(api_client, alice):
    res = api_client.post(
        "/auth/login", {"username": "alice", "password": "wrong"}, format="json"
    )
    assert res.status_code == 400


@pytest.mark.django_db
def test_logout_invalidates_token(api_client, alice):
    token, _ = Token.objects.get_or_create(user=alice)
    api_client.credentials(HTTP_AUTHORIZATION=f"Token {token.key}")
    res = api_client.post("/auth/logout")
    assert res.status_code == 204
    # 同じ token は無効化済み
    res2 = api_client.get("/auth/me")
    assert res2.status_code == 401


@pytest.mark.django_db
def test_unauthenticated_endpoints_return_401(api_client):
    for path in ("/auth/me", "/posts", "/users/alice/followers"):
        res = api_client.get(path)
        assert res.status_code == 401, f"{path} should require auth"
