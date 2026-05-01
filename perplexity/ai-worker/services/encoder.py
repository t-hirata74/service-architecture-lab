"""ADR 0002: 擬似 (deterministic) encoder.

入力テキストを 256 次元 float32 ベクトルに射影する。
本物の意味類似度は出ない (ローカル完結方針の意図した制約)。
学習対象は「scoring の構造 / embedding データ管理」であって精度ではない。

実装方針:
- 入力 text を hash で seed 化し、numpy.random.Generator で 256 次元ベクトル生成
- L2 正規化して cosine が +/-1 の範囲に収まるようにする
- decode は不可能 (一方向)
- version() を返し、chunks.embedding_version と一致させる
- 同一 text → 必ず同一 vector (再現性、テスト fixture に必要)
"""
from __future__ import annotations

import hashlib

import numpy as np

EMBEDDING_DIMS = 256
EMBEDDING_DTYPE = np.float32
ENCODER_VERSION = "mock-hash-v1"


def encode(text: str) -> np.ndarray:
    """Encode text to a 256-d float32 unit vector.

    deterministic: same input → identical output bytes.
    """
    seed = _stable_seed(text)
    rng = np.random.Generator(np.random.PCG64(seed))
    vec = rng.standard_normal(EMBEDDING_DIMS).astype(EMBEDDING_DTYPE)
    norm = np.linalg.norm(vec)
    if norm > 0:
        vec = vec / norm
    return vec.astype(EMBEDDING_DTYPE)


def encode_many(texts: list[str]) -> np.ndarray:
    """Vectorize a batch. Returns shape (N, 256) float32."""
    if not texts:
        return np.zeros((0, EMBEDDING_DIMS), dtype=EMBEDDING_DTYPE)
    return np.stack([encode(t) for t in texts], axis=0)


def version() -> str:
    return ENCODER_VERSION


def _stable_seed(text: str) -> int:
    # SHA-256 の先頭 8 byte (64-bit) を unsigned int として PCG64 seed に
    digest = hashlib.sha256(text.encode("utf-8")).digest()
    return int.from_bytes(digest[:8], byteorder="big", signed=False)
