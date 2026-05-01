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
