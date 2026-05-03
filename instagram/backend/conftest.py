"""Shared fixtures for instagram backend tests."""
from __future__ import annotations

import pytest
from rest_framework.authtoken.models import Token
from rest_framework.test import APIClient

# Celery を eager 実行にする (broker を立てずに task の同期検証を可能にする)。
# 注意: app.config_from_object("django.conf:settings") の挙動上、
# `app.conf.task_always_eager = True` を直接書いても settings 側を毎回読みに
# 行くので効かない。Django settings 側を書き換える必要がある。
from django.conf import settings as _settings

_settings.CELERY_TASK_ALWAYS_EAGER = True
_settings.CELERY_TASK_EAGER_PROPAGATES = True

from accounts.models import User


@pytest.fixture(autouse=True)
def _on_commit_runs_eagerly():
    """pytest-django のデフォルト transaction wrapper では on_commit hook が発火
    しない (各テストが nested transaction で wrap され rollback されるため)。
    テストでは callback を即時実行する形にスタブして fan-out signal を
    そのまま検証できるようにする。

    `monkeypatch` 経由だと pytest-django のテスト DB 周りで上書きされて
    効かないケースがあるので、ここでは module attribute を直接書き換えて
    yield 後に戻す。
    """
    from django.db import transaction as dj_tx

    original = dj_tx.on_commit
    dj_tx.on_commit = lambda func, *args, **kwargs: func()
    try:
        yield
    finally:
        dj_tx.on_commit = original


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
