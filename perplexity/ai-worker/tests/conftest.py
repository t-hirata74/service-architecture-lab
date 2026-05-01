"""pytest fixtures for ai-worker (ADR 0005).

MySQL に対する統合テストは `MYSQL_TEST_URL` env var が指定されている時のみ実行する.
ローカルでは perplexity_test を使う想定 (port 3310 / user perplexity).
"""
from __future__ import annotations

import os
import struct

import numpy as np
import pytest
from sqlalchemy import create_engine, text
from sqlalchemy.engine import Engine

from services import encoder

DEFAULT_TEST_URL = "mysql+pymysql://perplexity:perplexity@127.0.0.1:3310/perplexity_test?charset=utf8mb4"


def _engine_or_skip() -> Engine:
    url = os.getenv("MYSQL_TEST_URL", DEFAULT_TEST_URL)
    try:
        engine = create_engine(url, pool_pre_ping=True, future=True)
        with engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        return engine
    except Exception as e:  # noqa: BLE001
        pytest.skip(f"MySQL test DB not reachable ({url}): {e}")


@pytest.fixture
def mysql_engine() -> Engine:
    return _engine_or_skip()


def _embedding_bytes(vec: np.ndarray) -> bytes:
    """ADR 0002: little-endian float32 で chunks.embedding に詰める形と一致."""
    return b"".join(struct.pack("<f", float(v)) for v in vec)


@pytest.fixture
def seeded_corpus(mysql_engine: Engine):
    """3 件のテスト chunk (sources × 3 / 各 1 chunk) を MySQL test DB に投入する.

    chunks.embedding は本物の encoder で生成 (ADR 0002 の deterministic 性に依拠).
    yield 後に truncate.
    """
    docs = [
        {"id": 1001, "title": "Tower", "body": "東京タワーは 1958 年に完成した電波塔である。"},
        {"id": 1002, "title": "RAG",   "body": "RAG は検索と生成を組み合わせる LLM パターンである。"},
        {"id": 1003, "title": "SSE",   "body": "Server-Sent Events は単方向の HTTP ストリーミングである。"},
    ]
    version = encoder.version()

    with mysql_engine.begin() as conn:
        # truncate 前にきれいに
        conn.execute(text("DELETE FROM chunks"))
        conn.execute(text("DELETE FROM sources"))

        for d in docs:
            conn.execute(
                text("INSERT INTO sources (id, title, body, created_at, updated_at) VALUES (:id, :t, :b, NOW(), NOW())"),
                {"id": d["id"], "t": d["title"], "b": d["body"]},
            )
            vec = encoder.encode(d["body"])
            conn.execute(
                text(
                    """INSERT INTO chunks
                       (id, source_id, ord, chunker_version, body, embedding, embedding_version, created_at, updated_at)
                       VALUES (:id, :sid, 0, 'fixed-length-recursive-v1', :body, :emb, :ver, NOW(), NOW())"""
                ),
                {
                    "id": d["id"],
                    "sid": d["id"],
                    "body": d["body"],
                    "emb": _embedding_bytes(vec),
                    "ver": version,
                },
            )

    yield docs

    with mysql_engine.begin() as conn:
        conn.execute(text("DELETE FROM chunks"))
        conn.execute(text("DELETE FROM sources"))
