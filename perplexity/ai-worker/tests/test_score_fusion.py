"""ADR 0002: BM25 + cosine の min-max + weighted sum の純関数 unit-test."""
from __future__ import annotations

import pytest

from services.score_fusion import fuse, min_max_normalize


# ---- min_max_normalize ----


def test_min_max_normalize_basic():
    assert min_max_normalize([0.0, 5.0, 10.0]) == [0.0, 0.5, 1.0]


def test_min_max_normalize_all_equal_returns_zeros():
    """全件同点なら 0 (ランキングに寄与させない退化処理, ADR 0002 採用理由参照)."""
    assert min_max_normalize([3.0, 3.0, 3.0]) == [0.0, 0.0, 0.0]


def test_min_max_normalize_empty():
    assert min_max_normalize([]) == []


def test_min_max_normalize_single_value():
    # 単一要素も hi == lo の退化扱い
    assert min_max_normalize([7.5]) == [0.0]


# ---- fuse ----


def _setup():
    return {
        "bm25_hits": {1: 10.0, 2: 5.0, 3: 1.0},
        "cosine_hits": {1: 0.2, 2: 0.5, 3: 0.9},
        "chunk_to_source": {1: 100, 2: 200, 3: 300},
    }


def test_fuse_alpha_zero_uses_cosine_only():
    s = _setup()
    hits = fuse(**s, alpha=0.0, top_k=3)
    # cosine のみ → chunk 3 が最上位
    assert [h.chunk_id for h in hits] == [3, 2, 1]


def test_fuse_alpha_one_uses_bm25_only():
    s = _setup()
    hits = fuse(**s, alpha=1.0, top_k=3)
    # BM25 のみ → chunk 1 が最上位
    assert [h.chunk_id for h in hits] == [1, 2, 3]


def test_fuse_alpha_half_balances():
    s = _setup()
    hits = fuse(**s, alpha=0.5, top_k=3)
    # 1 と 3 の fused score: 0.5*1 + 0.5*0 = 0.5 / 0.5*0 + 0.5*1 = 0.5 → tie
    # 2 は 0.5*0.444 + 0.5*0.428 ≒ 0.436
    # 1 と 3 が tied (ties は安定ソート)、 2 が下
    top_ids = [h.chunk_id for h in hits]
    assert set(top_ids[:2]) == {1, 3}
    assert top_ids[2] == 2


def test_fuse_top_k_cuts_results():
    s = _setup()
    hits = fuse(**s, alpha=0.5, top_k=2)
    assert len(hits) == 2


def test_fuse_handles_disjoint_keys_with_zero_fill():
    """BM25 だけにある chunk / cosine だけにある chunk が混在しても OK."""
    hits = fuse(
        bm25_hits={1: 10.0, 2: 5.0},
        cosine_hits={2: 0.8, 3: 0.9},
        chunk_to_source={1: 100, 2: 200, 3: 300},
        alpha=0.5,
        top_k=3,
    )
    chunk_ids = [h.chunk_id for h in hits]
    assert set(chunk_ids) == {1, 2, 3}


def test_fuse_empty_inputs_returns_empty():
    hits = fuse(
        bm25_hits={},
        cosine_hits={},
        chunk_to_source={},
        alpha=0.5,
        top_k=10,
    )
    assert hits == []


def test_fuse_top_k_zero_returns_empty():
    s = _setup()
    assert fuse(**s, alpha=0.5, top_k=0) == []


def test_fuse_invalid_alpha_raises():
    s = _setup()
    with pytest.raises(ValueError):
        fuse(**s, alpha=-0.1, top_k=3)
    with pytest.raises(ValueError):
        fuse(**s, alpha=1.5, top_k=3)


def test_fuse_carries_source_id():
    s = _setup()
    hits = fuse(**s, alpha=0.5, top_k=3)
    by_id = {h.chunk_id: h for h in hits}
    assert by_id[1].source_id == 100
    assert by_id[3].source_id == 300
