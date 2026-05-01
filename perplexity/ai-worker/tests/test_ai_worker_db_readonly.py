"""ADR 0001 / 0005: ai-worker は MySQL に対して読み専 — INSERT/UPDATE/DELETE/DDL を発行しない.

SQLAlchemy の `before_cursor_execute` event で実行 SQL を全件記録し、
書き込み系の文が 1 つでも出ていたら fail させる.
"""
from __future__ import annotations

import re

import pytest
from sqlalchemy import create_engine, event, text

from services.embedding_store import EmbeddingStore
from services.retriever import Retriever, to_boolean_query


WRITE_SQL_PATTERN = re.compile(
    r"^\s*(INSERT|UPDATE|DELETE|REPLACE|CREATE|DROP|ALTER|TRUNCATE|RENAME|GRANT|REVOKE)\b",
    re.IGNORECASE,
)


@pytest.fixture
def recording_engine():
    """In-memory SQLite で本物の SQL をキャプチャする (MySQL 専用構文を避けて統合用).

    本テストの目的は `chunks` テーブルが存在するかではなく、ai-worker のコードが
    INSERT/UPDATE/DELETE 系の SQL を発行しないことを SQL 文字列レベルで検査すること.
    """
    engine = create_engine("sqlite:///:memory:", future=True)
    statements: list[str] = []

    @event.listens_for(engine, "before_cursor_execute")
    def _capture(conn, cursor, statement, params, context, executemany):  # noqa: ARG001
        statements.append(statement)

    # ai-worker が触るテーブル相当を作る (sqlite なので MySQL FULLTEXT は省略).
    with engine.begin() as conn:
        conn.execute(text("CREATE TABLE chunks (id INTEGER PRIMARY KEY, source_id INTEGER, body TEXT, embedding BLOB, embedding_version TEXT)"))

    statements.clear()  # 前準備の DDL は除外
    return engine, statements


def test_embedding_store_load_only_selects(recording_engine):
    engine, statements = recording_engine
    store = EmbeddingStore(engine=engine, embedding_version="mock-hash-v1")
    store.load()
    assert statements, "expected at least one statement"
    for sql in statements:
        assert not WRITE_SQL_PATTERN.match(sql), f"ai-worker emitted write SQL: {sql!r}"


def test_retriever_retrieve_only_selects(recording_engine):
    engine, statements = recording_engine
    store = EmbeddingStore(engine=engine, embedding_version="mock-hash-v1")
    store.load()
    statements.clear()

    retriever = Retriever(engine=engine, store=store)
    # bm25 SQL を avoid するため空クエリで run (cosine だけ動く)
    # 本テストは「書き込み SQL が出ない」ことだけ確認するので、空 store でも有効
    try:
        retriever.retrieve("テストクエリ", top_k=3, alpha=0.5)
    except Exception:
        # SQLite には MATCH AGAINST が無いので fail し得るが、 statements は記録される
        pass

    for sql in statements:
        assert not WRITE_SQL_PATTERN.match(sql), f"ai-worker emitted write SQL: {sql!r}"


def test_to_boolean_query_does_not_touch_db(recording_engine):
    """retriever の純関数経路は DB に触らない — sanity check."""
    _engine, statements = recording_engine
    statements.clear()
    to_boolean_query("foo +bar -baz")
    assert statements == []
