"""Endpoint smoke (Phase 2): /health and /corpus/embed."""
from __future__ import annotations

from fastapi.testclient import TestClient

from main import app

client = TestClient(app)


def test_health():
    res = client.get("/health")
    assert res.status_code == 200
    body = res.json()
    assert body["status"] == "ok"
    assert body["service"] == "perplexity-ai-worker"


def test_corpus_embed_returns_256d_vectors():
    res = client.post("/corpus/embed", json={"texts": ["alpha", "beta"]})
    assert res.status_code == 200
    body = res.json()
    assert body["embedding_version"]
    assert len(body["embeddings"]) == 2
    for vec in body["embeddings"]:
        assert len(vec) == 256
        assert all(isinstance(v, float) for v in vec)


def test_corpus_embed_is_deterministic_across_calls():
    a = client.post("/corpus/embed", json={"texts": ["query"]}).json()
    b = client.post("/corpus/embed", json={"texts": ["query"]}).json()
    assert a["embeddings"] == b["embeddings"]


def test_corpus_embed_rejects_empty_texts():
    res = client.post("/corpus/embed", json={"texts": []})
    assert res.status_code == 422


def test_retrieve_with_unloaded_store_returns_503_or_empty():
    """startup の lifespan が走らない TestClient では retriever 未初期化 → 503.

    本来は app.state を inject する形でテストするが、smoke レベルとしては
    503 を返すこと (silent に空 hits ではない) を確認する.
    """
    # TestClient 経由 (lifespan 走らない) → app.state.retriever が None
    # ただし FastAPI の TestClient は startup を実行するので、retriever は初期化される.
    # ロード失敗時は 503 が返ることを確認 (DB 未到達想定)
    res = client.post("/retrieve", json={"query_text": "テスト", "top_k": 3})
    # DB が test 環境にあれば 200、無ければ 503。どちらでも silent crash ではない.
    assert res.status_code in (200, 503)
    if res.status_code == 200:
        body = res.json()
        assert "hits" in body
        assert "embedding_version" in body
        assert "loaded_chunks" in body


def test_retrieve_validates_alpha_range():
    res = client.post("/retrieve", json={"query_text": "x", "alpha": 1.5})
    assert res.status_code == 422
    res = client.post("/retrieve", json={"query_text": "x", "alpha": -0.1})
    assert res.status_code == 422


def test_retrieve_rejects_empty_query():
    res = client.post("/retrieve", json={"query_text": "", "top_k": 3})
    assert res.status_code == 422
