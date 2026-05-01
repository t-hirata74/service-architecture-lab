"""ADR 0001 Phase 3: /extract ステージ.

retrieve で得た chunk_ids を、synthesize に渡せる passage 形式に整形する.
Phase 3 では snippet = chunk.body そのまま (highlight / 切り出しは Phase 4 以降).

ai-worker は MySQL 読み専 (ADR 0001) なので EmbeddingStore のキャッシュから
chunk 本文を引く (cold start でロード済み).
"""
from __future__ import annotations

from dataclasses import dataclass

from services.embedding_store import EmbeddingStore


@dataclass(frozen=True)
class Passage:
    chunk_id: int
    source_id: int
    snippet: str
    ord: int  # extract 入力 chunk_ids 配列内の位置 (synthesize での順序キーに使う)


class Extractor:
    def __init__(self, store: EmbeddingStore):
        self._store = store

    def extract(self, chunk_ids: list[int]) -> list[Passage]:
        """chunk_ids の順序を保ったまま passage 化. 不在 chunk は skip."""
        passages: list[Passage] = []
        source_by_id = self._store.chunk_to_source()
        for ord_, cid in enumerate(chunk_ids):
            body = self._store.chunk_body(cid)
            if body is None:
                continue  # rechunk 等で消えた chunk はスキップ
            passages.append(
                Passage(
                    chunk_id=cid,
                    source_id=source_by_id.get(cid, 0),
                    snippet=body,
                    ord=ord_,
                )
            )
        return passages
