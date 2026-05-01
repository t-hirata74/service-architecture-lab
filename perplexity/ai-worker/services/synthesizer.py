"""ADR 0001 / 0003 / 0004: synthesize ステージ (mock LLM SSE).

retrieve + extract の出力を context として「クエリに対する引用付き回答」を
SSE で逐次生成する。本物の LLM ではなく、passage を素直に並べて引用 marker
([#src_<id>]) を貼った文字列を 3-5 chunk に分けて yield する.

ADR 0004: ai-worker は allowed_source_ids 集合外の id を marker として吐かない
ことを self-defense (warn) で確認する。Rails 側で再検証されるため
panic ではなく logger.warning に留める.

fixture モード:
  SYNTHESIZER_FIXTURE=invalid を ENV で指定すると、allowed_source_ids 外の id
  を 1 つ混ぜる (Phase 4 の citation_invalid デモ用).
"""
from __future__ import annotations

import json
import logging
import os
from typing import AsyncIterator

from services.extractor import Passage

logger = logging.getLogger(__name__)


def _format_event(name: str, payload: dict) -> bytes:
    """SSE event 1 件を text/event-stream 仕様で bytes に直列化."""
    data = json.dumps(payload, ensure_ascii=False)
    return f"event: {name}\ndata: {data}\n\n".encode("utf-8")


def _truncate(text: str, n: int = 80) -> str:
    if len(text) <= n:
        return text
    return text[: n - 1] + "…"


async def synthesize_stream(
    query_text: str,
    passages: list[Passage],
    allowed_source_ids: list[int],
) -> AsyncIterator[bytes]:
    """Yield SSE bytes (event chunks → citation events → done)."""
    allowed_set = set(allowed_source_ids)
    fixture = os.getenv("SYNTHESIZER_FIXTURE", "").lower()

    body_so_far = ""

    # 1. 導入 chunk
    intro = f"クエリ「{_truncate(query_text, 60)}」について、関連情報をまとめます。"
    yield _format_event("chunk", {"text": intro, "ord": 0})
    body_so_far += intro

    # 2. 各 passage を 1 chunk としてサーブ + citation event
    used_passages = passages[:3]  # 3 件まで
    for i, passage in enumerate(used_passages, start=1):
        marker_text = f"[#src_{passage.source_id}]"
        snippet = _truncate(passage.snippet, 100)
        chunk_text = f" {snippet} {marker_text}"

        yield _format_event("chunk", {"text": chunk_text, "ord": i})
        position = len(body_so_far) + chunk_text.rindex(marker_text)
        body_so_far += chunk_text

        # ADR 0004: ai-worker 自衛 — allowed 外なら warn (Rails で再検証)
        if passage.source_id not in allowed_set:
            logger.warning(
                "synthesizer emitted source_id %s not in allowed_source_ids",
                passage.source_id,
            )

        yield _format_event(
            "citation",
            {
                "marker": f"src_{passage.source_id}",
                "source_id": passage.source_id,
                "chunk_id": passage.chunk_id,
                "position": position,
                "valid": passage.source_id in allowed_set,
            },
        )

    # 3. fixture モード: 不正引用を 1 件混ぜる (Phase 4 の citation_invalid デモ用)
    if fixture == "invalid":
        bogus_id = max(allowed_set, default=0) + 9999
        bogus_marker = f"[#src_{bogus_id}]"
        bogus_text = f" この情報は架空のソースです。{bogus_marker}"
        yield _format_event("chunk", {"text": bogus_text, "ord": len(used_passages) + 1})
        position = len(body_so_far) + bogus_text.rindex(bogus_marker)
        body_so_far += bogus_text
        logger.warning("synthesizer emitted out-of-allowed source_id %s (fixture=invalid)", bogus_id)
        yield _format_event(
            "citation",
            {
                "marker": f"src_{bogus_id}",
                "source_id": bogus_id,
                "chunk_id": 0,
                "position": position,
                "valid": False,
            },
        )

    # 4. done
    yield _format_event(
        "done",
        {
            "chunks": 1 + len(used_passages) + (1 if fixture == "invalid" else 0),
            "body_length": len(body_so_far),
        },
    )
