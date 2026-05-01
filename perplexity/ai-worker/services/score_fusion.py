"""ADR 0002: BM25 と cosine スコアの統合 (min-max 正規化 + 重み付き和).

純関数群。retriever / encoder と独立にテスト可能。
"""
from __future__ import annotations

from dataclasses import dataclass

import numpy as np


@dataclass(frozen=True)
class FusedHit:
    chunk_id: int
    source_id: int
    bm25_score: float
    cosine_score: float
    fused_score: float


def min_max_normalize(values: list[float]) -> list[float]:
    """[0, 1] にスケール。全件同点なら全て 0 とする (ランキングに寄与させない)."""
    if not values:
        return []
    arr = np.array(values, dtype=np.float64)
    lo, hi = arr.min(), arr.max()
    if hi == lo:
        return [0.0] * len(values)
    return ((arr - lo) / (hi - lo)).tolist()


def fuse(
    *,
    bm25_hits: dict[int, float],
    cosine_hits: dict[int, float],
    chunk_to_source: dict[int, int],
    alpha: float = 0.5,
    top_k: int = 10,
) -> list[FusedHit]:
    """BM25 と cosine の min-max 正規化 + 重み付き和で上位 top_k を返す.

    どちらか一方の hits だけに含まれる chunk_id は他方を 0 として扱う
    (片方のスコアだけで上位に来ることは許容する: hybrid の片肺ケース).

    Args:
        bm25_hits: chunk_id -> BM25 score (絶対値、 高いほど良い)
        cosine_hits: chunk_id -> cosine 類似度 (-1.0 〜 1.0、 高いほど良い)
        chunk_to_source: chunk_id -> source_id
        alpha: fused = alpha * bm25_norm + (1 - alpha) * cosine_norm. 範囲 [0, 1].
        top_k: 上位件数
    """
    if not (0.0 <= alpha <= 1.0):
        raise ValueError(f"alpha must be in [0, 1], got {alpha}")
    if top_k <= 0:
        return []

    chunk_ids = list({*bm25_hits.keys(), *cosine_hits.keys()})
    if not chunk_ids:
        return []

    bm25_raw = [bm25_hits.get(cid, 0.0) for cid in chunk_ids]
    cosine_raw = [cosine_hits.get(cid, 0.0) for cid in chunk_ids]
    bm25_norm = min_max_normalize(bm25_raw)
    cosine_norm = min_max_normalize(cosine_raw)

    fused = []
    for cid, bm, co, bn, cn in zip(chunk_ids, bm25_raw, cosine_raw, bm25_norm, cosine_norm):
        fused.append(
            FusedHit(
                chunk_id=cid,
                source_id=chunk_to_source.get(cid, 0),
                bm25_score=bm,
                cosine_score=co,
                fused_score=alpha * bn + (1 - alpha) * cn,
            )
        )

    fused.sort(key=lambda h: h.fused_score, reverse=True)
    return fused[:top_k]
