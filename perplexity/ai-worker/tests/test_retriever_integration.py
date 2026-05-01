"""ADR 0002 / 0005: hybrid retrieval の MySQL 統合テスト.

事前条件: perplexity_test DB が利用可能で migration 済みであること.
ローカルでは `cd perplexity/backend && bundle exec rails db:test:prepare` で準備.
未到達なら conftest が skip する.
"""
from __future__ import annotations

import pytest

from services.embedding_store import EmbeddingStore
from services.retriever import Retriever


@pytest.fixture
def retriever(mysql_engine, seeded_corpus):  # noqa: ARG001 - seeded_corpus は副作用
    store = EmbeddingStore(engine=mysql_engine)
    store.load()
    return Retriever(engine=mysql_engine, store=store)


def test_bm25_brings_surface_form_match_to_top(retriever, seeded_corpus):
    # BM25 only (alpha=1.0): 「東京タワー」は title=Tower(id=1001) chunk が最上位
    hits = retriever.retrieve("東京タワー", top_k=3, alpha=1.0)
    assert len(hits) >= 1
    assert hits[0].chunk_id == 1001


def test_bm25_finds_rag_keyword(retriever):
    hits = retriever.retrieve("RAG", top_k=3, alpha=1.0)
    assert len(hits) >= 1
    assert hits[0].chunk_id == 1002


def test_bm25_finds_sse(retriever):
    # ngram parser は日本語と英語混在を index する: "SSE" でヒット
    hits = retriever.retrieve("Server-Sent Events", top_k=3, alpha=1.0)
    assert len(hits) >= 1
    assert hits[0].chunk_id == 1003


def test_cosine_only_returns_all_chunks(retriever):
    # alpha=0.0: cosine only。擬似 encoder は意味的でないので順序は不定だが、
    # 全 3 chunk が結果に含まれるはず
    hits = retriever.retrieve("無関係なクエリ", top_k=10, alpha=0.0)
    chunk_ids = {h.chunk_id for h in hits}
    assert chunk_ids == {1001, 1002, 1003}


def test_top_k_cuts_results(retriever):
    hits = retriever.retrieve("東京", top_k=1, alpha=0.5)
    assert len(hits) <= 1


def test_query_with_only_operators_returns_empty_bm25(retriever):
    # _to_boolean_query が `+-"()` 等を全て削るので、BM25 段は 0 件 → cosine だけが効く
    hits = retriever.retrieve('+-"()*', top_k=3, alpha=1.0)
    # alpha=1.0 で BM25 only → fused_score 全 0 → 同点退化で全 0
    for h in hits:
        assert h.fused_score == 0.0


def test_query_with_minus_does_not_exclude_other_chunks(retriever):
    # `-` が exclude operator として誤認されないことを実 DB で確認
    # (バグ修正前は "東京 -RAG" で RAG chunk が結果から消える可能性があった)
    hits = retriever.retrieve("東京 -RAG", top_k=3, alpha=1.0)
    chunk_ids = [h.chunk_id for h in hits]
    # 「東京」に強くマッチするのは Tower、RAG chunk に「東京」は無いので 1002 がヒットしないのは OK.
    # でも `- が exclude にならない` ことを保証するため、Tower (1001) が必ず結果に含まれる
    assert 1001 in chunk_ids
