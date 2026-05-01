"""Phase 3: extractor unit tests."""
from __future__ import annotations

import pytest

from services.embedding_store import EmbeddingStore, Snapshot, StoredChunk
from services.extractor import Extractor


@pytest.fixture
def store_with_chunks():
    chunks = (
        StoredChunk(chunk_id=10, source_id=1, body="本文 A"),
        StoredChunk(chunk_id=20, source_id=2, body="本文 B"),
        StoredChunk(chunk_id=30, source_id=3, body="本文 C"),
    )
    snap = Snapshot(
        chunks=chunks,
        matrix=Snapshot.empty().matrix,
        body_by_id={c.chunk_id: c.body for c in chunks},
        source_by_id={c.chunk_id: c.source_id for c in chunks},
    )
    store = EmbeddingStore.__new__(EmbeddingStore)
    store._snapshot = snap
    store._loaded = True
    store._engine = None
    store._embedding_version = None
    return store


def test_extract_preserves_input_order(store_with_chunks):
    extractor = Extractor(store=store_with_chunks)
    result = extractor.extract([20, 10, 30])
    assert [p.chunk_id for p in result] == [20, 10, 30]
    assert [p.ord for p in result] == [0, 1, 2]


def test_extract_carries_source_id_and_snippet(store_with_chunks):
    extractor = Extractor(store=store_with_chunks)
    result = extractor.extract([20])
    assert result[0].source_id == 2
    assert result[0].snippet == "本文 B"


def test_extract_skips_unknown_chunk_ids(store_with_chunks):
    extractor = Extractor(store=store_with_chunks)
    result = extractor.extract([10, 9999, 30])
    assert [p.chunk_id for p in result] == [10, 30]


def test_extract_empty_input(store_with_chunks):
    extractor = Extractor(store=store_with_chunks)
    assert extractor.extract([]) == []
