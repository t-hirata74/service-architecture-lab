"""ai-worker のテストは MySQL を立てずに sqlite で seed する。
SQL は MySQL 系だが SELECT/JOIN/LIMIT のみで sqlite 互換。
"""
from __future__ import annotations

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, text
from sqlalchemy.pool import StaticPool

from main import app, get_engine


@pytest.fixture
def seeded_engine():
    # StaticPool で 1 connection を使い回さないと :memory: が
    # connect() のたびに別 DB になる。
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    with engine.begin() as conn:
        conn.execute(
            text(
                "CREATE TABLE posts ("
                "  id INTEGER PRIMARY KEY,"
                "  user_id INTEGER NOT NULL,"
                "  deleted_at TIMESTAMP NULL,"
                "  created_at TIMESTAMP NOT NULL"
                ")"
            )
        )
        conn.execute(
            text(
                "CREATE TABLE follow_edges ("
                "  id INTEGER PRIMARY KEY,"
                "  follower_id INTEGER NOT NULL,"
                "  followee_id INTEGER NOT NULL"
                ")"
            )
        )
        # users:
        # 1 = viewer (alice)
        # 2 = bob (alice follows)
        # 3 = carol (alice does not follow)
        # 4 = dave (alice does not follow)
        conn.execute(
            text(
                "INSERT INTO posts (id, user_id, deleted_at, created_at) VALUES"
                " (10, 2, NULL, '2026-01-01 10:00:00'),"  # bob (followed) — 除外
                " (11, 3, NULL, '2026-01-02 10:00:00'),"  # carol — 採用
                " (12, 4, NULL, '2026-01-03 10:00:00'),"  # dave — 採用 (newest)
                " (13, 4, '2026-01-04 10:00:00', '2026-01-03 10:00:00'),"  # deleted
                " (14, 1, NULL, '2026-01-05 10:00:00')"  # alice 自身 — 除外
            )
        )
        conn.execute(
            text(
                "INSERT INTO follow_edges (id, follower_id, followee_id) VALUES"
                " (1, 1, 2)"  # alice → bob
            )
        )
    return engine


@pytest.fixture
def client(seeded_engine):
    app.dependency_overrides[get_engine] = lambda: seeded_engine
    yield TestClient(app)
    app.dependency_overrides.clear()
