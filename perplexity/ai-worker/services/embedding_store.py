"""ADR 0002: cold start で chunks.embedding 全件を numpy in-memory にロードし、
クエリ embedding との cosine 類似度を一括計算する.

memory: 256-d float32 = 1024 byte / chunk。1 万 chunk で 10 MB。
本番想定でこれを越えるなら Faiss / OpenSearch (Terraform 設計図) に切り替える.

Rails ↔ ai-worker は SQLAlchemy で同 MySQL を共有 (ADR 0001: ai-worker は読み専).

並行性 (レビュー指摘 §3.2 への対応):
- snapshot pattern: (chunks, matrix, body_index, source_index) を 1 つの immutable
  Snapshot にまとめ、reload 時は新 Snapshot を構築して **属性を 1 行で差し替え**.
- retrieve 中の読み手は self._snapshot を 1 度だけ参照すれば、その間 Snapshot は
  GC されない (Python の reference 取得は atomic)。整合性が崩れない.
- chunk_body / chunk_to_source は dict ベースで O(1) 化 (レビュー指摘 §3.3).
"""
from __future__ import annotations

import logging
import os
from dataclasses import dataclass

import numpy as np
from sqlalchemy import create_engine, text
from sqlalchemy.engine import Engine

logger = logging.getLogger(__name__)

EMBEDDING_DIMS = 256
EMBEDDING_DTYPE = np.float32
EMBEDDING_BYTES = EMBEDDING_DIMS * 4  # float32 = 4 byte


@dataclass(frozen=True)
class StoredChunk:
    chunk_id: int
    source_id: int
    body: str


@dataclass(frozen=True)
class Snapshot:
    """ロード結果の immutable スナップショット. 入れ替えは属性代入 1 回で原子的."""
    chunks: tuple[StoredChunk, ...]
    matrix: np.ndarray  # shape (N, 256) or (0, 256)
    body_by_id: dict[int, str]
    source_by_id: dict[int, int]

    @classmethod
    def empty(cls) -> "Snapshot":
        return cls(chunks=(), matrix=np.zeros((0, EMBEDDING_DIMS), dtype=EMBEDDING_DTYPE),
                   body_by_id={}, source_by_id={})


class EmbeddingStore:
    """cold start で全件ロード。retrieve 中はロックなしで read-only."""

    def __init__(self, engine: Engine | None = None, embedding_version: str | None = None):
        self._engine = engine or _build_default_engine()
        self._embedding_version = embedding_version  # None = ENV / encoder.version() に追従
        self._snapshot: Snapshot = Snapshot.empty()
        self._loaded = False

    @property
    def loaded(self) -> bool:
        return self._loaded

    @property
    def size(self) -> int:
        return len(self._snapshot.chunks)

    def load(self) -> int:
        """対象 embedding_version の chunk を numpy にロード. ロード件数を返す."""
        from services import encoder  # 循環 import 回避のため局所

        version = self._embedding_version or encoder.version()
        with self._engine.connect() as conn:
            rows = conn.execute(
                text(
                    """
                    SELECT id, source_id, body, embedding
                    FROM chunks
                    WHERE embedding IS NOT NULL
                      AND embedding_version = :v
                    ORDER BY id
                    """
                ),
                {"v": version},
            ).fetchall()

        chunks: list[StoredChunk] = []
        vectors: list[np.ndarray] = []
        body_by_id: dict[int, str] = {}
        source_by_id: dict[int, int] = {}
        for row in rows:
            blob = row.embedding
            if blob is None or len(blob) != EMBEDDING_BYTES:
                logger.warning("skipping chunk %s: invalid embedding length", row.id)
                continue
            vec = np.frombuffer(blob, dtype="<f4")  # little-endian float32, ADR 0002
            chunk = StoredChunk(chunk_id=row.id, source_id=row.source_id, body=row.body)
            chunks.append(chunk)
            vectors.append(vec)
            body_by_id[row.id] = row.body
            source_by_id[row.id] = row.source_id

        matrix = (
            np.stack(vectors, axis=0).astype(EMBEDDING_DTYPE)
            if vectors
            else np.zeros((0, EMBEDDING_DIMS), dtype=EMBEDDING_DTYPE)
        )
        new_snapshot = Snapshot(
            chunks=tuple(chunks),
            matrix=matrix,
            body_by_id=body_by_id,
            source_by_id=source_by_id,
        )

        # 属性差し替えは Python の単一代入で atomic (GIL 下).
        # 旧 snapshot を参照中の retrieve は最後まで一貫した値を見る.
        self._snapshot = new_snapshot
        self._loaded = True

        logger.info("EmbeddingStore loaded %d chunks (version=%s)", len(chunks), version)
        return len(chunks)

    def cosine_against(self, query_vec: np.ndarray) -> dict[int, float]:
        """クエリベクタとの cosine 類似度. encoder の出力は単位ベクタなので内積 = cosine."""
        snap = self._snapshot
        if snap.matrix.shape[0] == 0:
            return {}
        # encoder が L2 正規化済み → 内積で OK
        scores = snap.matrix @ query_vec.astype(EMBEDDING_DTYPE)
        return {snap.chunks[i].chunk_id: float(scores[i]) for i in range(len(snap.chunks))}

    def chunk_to_source(self) -> dict[int, int]:
        # 呼び出し側に変更させないよう shallow copy
        return dict(self._snapshot.source_by_id)

    def chunk_body(self, chunk_id: int) -> str | None:
        return self._snapshot.body_by_id.get(chunk_id)


def _build_default_engine() -> Engine:
    url = os.getenv(
        "DATABASE_URL",
        "mysql+pymysql://perplexity:perplexity@127.0.0.1:3310/perplexity_development?charset=utf8mb4",
    )
    return create_engine(url, pool_pre_ping=True, future=True)
