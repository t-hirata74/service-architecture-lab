"""ADR 0002: 擬似 encoder の不変条件 (deterministic / 256-d / float32 / 単位ベクタ)."""
from __future__ import annotations

import numpy as np
import pytest

from services import encoder


def test_encode_returns_256d_float32():
    vec = encoder.encode("東京タワーは 1958 年に完成した。")
    assert vec.shape == (256,)
    assert vec.dtype == np.float32


def test_encode_is_deterministic():
    a = encoder.encode("hello world")
    b = encoder.encode("hello world")
    assert np.array_equal(a, b)


def test_encode_differs_for_different_inputs():
    a = encoder.encode("query A")
    b = encoder.encode("query B")
    # ハッシュ衝突が起きない限り異なる
    assert not np.array_equal(a, b)


def test_encode_unit_norm():
    vec = encoder.encode("適度な長さの日本語クエリ")
    assert np.linalg.norm(vec) == pytest.approx(1.0, abs=1e-5)


def test_encode_many_shape():
    matrix = encoder.encode_many(["a", "b", "c"])
    assert matrix.shape == (3, 256)
    assert matrix.dtype == np.float32


def test_encode_many_empty_input():
    matrix = encoder.encode_many([])
    assert matrix.shape == (0, 256)
    assert matrix.dtype == np.float32


def test_version_is_stable_string():
    v = encoder.version()
    assert isinstance(v, str)
    assert len(v) <= 64  # chunks.embedding_version VARCHAR(64) と整合
