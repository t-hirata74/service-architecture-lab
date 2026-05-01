"""ADR 0002: hybrid retrieval (BM25 + cosine) の orchestrator.

- BM25: MySQL FULLTEXT MATCH AGAINST IN BOOLEAN MODE (chunks.body, ngram parser)
- cosine: EmbeddingStore (numpy in-memory) で計算
- 統合: services.score_fusion (純関数)
"""
from __future__ import annotations

import logging

from sqlalchemy import text
from sqlalchemy.engine import Engine

from services import encoder
from services.embedding_store import EmbeddingStore
from services.score_fusion import FusedHit, fuse

logger = logging.getLogger(__name__)

DEFAULT_TOP_K = 10
DEFAULT_ALPHA = 0.5
BM25_FETCH_LIMIT = 100  # BM25 段で多めに取り、cosine で再ランク
NGRAM_MIN_TOKEN_SIZE = 2  # MySQL ngram parser の最小マッチ長

# MySQL FULLTEXT BOOLEAN MODE の operator (これらが含まれるとクエリ意味が変わる).
# +foo, -foo, "phrase", (group), ~lower, foo*, <less, >more, @ (proximity).
# パラメタライズ済みなので SQL injection ではないが、ユーザクエリの意味を壊す.
_BOOLEAN_OPERATORS = frozenset('+-"()~*<>@\\\'')


class Retriever:
    def __init__(self, engine: Engine, store: EmbeddingStore):
        self._engine = engine
        self._store = store

    def retrieve(self, query_text: str, top_k: int = DEFAULT_TOP_K, alpha: float = DEFAULT_ALPHA) -> list[FusedHit]:
        bm25_hits = self._bm25(query_text, limit=BM25_FETCH_LIMIT)
        cosine_hits = self._cosine(query_text)

        # cosine だけ高い chunk も上位に拾えるよう、両方のキーを union
        return fuse(
            bm25_hits=bm25_hits,
            cosine_hits=cosine_hits,
            chunk_to_source=self._store.chunk_to_source(),
            alpha=alpha,
            top_k=top_k,
        )

    def _bm25(self, query_text: str, limit: int) -> dict[int, float]:
        # MySQL FULLTEXT BOOLEAN MODE は **空白を boolean separator** として扱うため、
        # 日本語の連続したフレーズを 1 phrase として完全一致検索してしまう
        # (例: "東京タワーはいつ完成した" だと 12 文字ぴったりの一致を要求).
        # NATURAL LANGUAGE MODE なら ngram parser がクエリ側も 2-gram にトークナイズし、
        # OR 検索として動くので長文クエリでも spread する.
        # 安全性: BOOLEAN operator は to_boolean_query で剥がし済み.
        sanitized = to_boolean_query(query_text)
        if not sanitized:
            return {}

        with self._engine.connect() as conn:
            rows = conn.execute(
                text(
                    """
                    SELECT id, MATCH(body) AGAINST(:q IN NATURAL LANGUAGE MODE) AS score
                    FROM chunks
                    WHERE MATCH(body) AGAINST(:q IN NATURAL LANGUAGE MODE)
                    ORDER BY score DESC
                    LIMIT :lim
                    """
                ),
                {"q": sanitized, "lim": limit},
            ).fetchall()
        return {row.id: float(row.score) for row in rows}

    def _cosine(self, query_text: str) -> dict[int, float]:
        if self._store.size == 0:
            return {}
        qvec = encoder.encode(query_text)
        return self._store.cosine_against(qvec)


def to_boolean_query(query_text: str) -> str:
    """Sanitize a user query for MySQL FULLTEXT BOOLEAN MODE.

    - BOOLEAN operator chars (+ - " ( ) ~ * < > @ \\ ') を空白に置換
    - 連続空白を 1 個に圧縮
    - 最小 token 長 (ngram min_token_size = 2) 未満の token を捨てる
    - ngram parser は CJK / Latin を区別なく n-gram で索引するので、
      日本語英語混在クエリにそのまま使える

    >>> to_boolean_query('foo "bar" -baz')
    'foo bar baz'
    >>> to_boolean_query('a +b')
    'b'
    """
    cleaned = "".join(" " if ch in _BOOLEAN_OPERATORS else ch for ch in query_text)
    tokens = [t for t in cleaned.split() if len(t) >= NGRAM_MIN_TOKEN_SIZE]
    return " ".join(tokens)
