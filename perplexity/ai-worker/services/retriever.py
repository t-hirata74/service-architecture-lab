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
        # MySQL FULLTEXT は + や " のような演算子が含まれるとエラーになるので escape する.
        # クエリは boolean mode で全 token を含む形に: "東京 タワー" → "+東京 +タワー"
        boolean_query = self._to_boolean_query(query_text)
        if not boolean_query:
            return {}

        with self._engine.connect() as conn:
            rows = conn.execute(
                text(
                    """
                    SELECT id, MATCH(body) AGAINST(:q IN BOOLEAN MODE) AS score
                    FROM chunks
                    WHERE MATCH(body) AGAINST(:q IN BOOLEAN MODE)
                    ORDER BY score DESC
                    LIMIT :lim
                    """
                ),
                {"q": boolean_query, "lim": limit},
            ).fetchall()
        return {row.id: float(row.score) for row in rows}

    def _cosine(self, query_text: str) -> dict[int, float]:
        if self._store.size == 0:
            return {}
        qvec = encoder.encode(query_text)
        return self._store.cosine_against(qvec)

    @staticmethod
    def _to_boolean_query(query_text: str) -> str:
        """ngram parser 向けに boolean operator を除去し、空白区切りに."""
        # 危険な文字を消す: + - " ' ( ) ~ * < > @ ! を space に
        cleaned = "".join(ch if ch.isalnum() or ch in "ぁ-んァ-ヶ亜-熙 　" else " " for ch in query_text)
        tokens = [t for t in cleaned.split() if t]
        if not tokens:
            return ""
        # boolean mode で全 token を「あれば優先」(必須でない) にして OR 結合
        return " ".join(tokens)
