"""Phase 3: synthesizer (mock LLM SSE) の不変条件 + ADR 0004 self-defense."""
from __future__ import annotations

import json
import os
from typing import AsyncIterator

import pytest

from services.extractor import Passage
from services.synthesizer import synthesize_stream


def _events_from(stream: AsyncIterator[bytes]) -> list[dict]:
    """SSE バイト列を { event, data } のリストに変換 (sync 試験用)."""
    import asyncio

    async def _collect():
        chunks: list[bytes] = []
        async for b in stream:
            chunks.append(b)
        return b"".join(chunks)

    raw = asyncio.run(_collect()).decode("utf-8")
    events: list[dict] = []
    for block in raw.strip().split("\n\n"):
        if not block:
            continue
        event = None
        data = None
        for line in block.split("\n"):
            if line.startswith("event:"):
                event = line[len("event:"):].strip()
            elif line.startswith("data:"):
                data = line[len("data:"):].strip()
        events.append({"event": event, "data": json.loads(data) if data else None})
    return events


@pytest.fixture
def passages():
    return [
        Passage(chunk_id=1, source_id=10, snippet="東京タワーは 1958 年に完成した。", ord=0),
        Passage(chunk_id=2, source_id=20, snippet="RAG は検索と生成の組み合わせ。", ord=1),
    ]


def test_emits_chunk_then_citation_then_done(passages):
    events = _events_from(synthesize_stream("query", passages, [10, 20]))
    names = [e["event"] for e in events]
    assert names[0] == "chunk"  # intro
    assert "done" == names[-1]
    # 各 passage に対して chunk + citation のペアが続く
    assert names.count("chunk") == 1 + len(passages)
    assert names.count("citation") == len(passages)


def test_citation_position_points_to_marker_in_body(passages):
    events = _events_from(synthesize_stream("query", passages, [10, 20]))
    body = "".join(e["data"]["text"] for e in events if e["event"] == "chunk")
    for e in events:
        if e["event"] == "citation":
            position = e["data"]["position"]
            marker = e["data"]["marker"]
            # body[position:] が "[#src_<id>]" で始まる
            assert body[position : position + len(marker) + 3] == f"[#{marker}]"


def test_citation_valid_flag_true_when_in_allowed(passages):
    events = _events_from(synthesize_stream("query", passages, [10, 20]))
    citations = [e for e in events if e["event"] == "citation"]
    assert all(c["data"]["valid"] for c in citations)


def test_citation_valid_flag_false_when_outside_allowed(passages):
    # source_id=10 だけ allowed → source_id=20 の citation は valid: False
    events = _events_from(synthesize_stream("query", passages, [10]))
    citations = {e["data"]["source_id"]: e["data"]["valid"] for e in events if e["event"] == "citation"}
    assert citations[10] is True
    assert citations[20] is False  # ADR 0004 の self-defense (warn only, but flag = False)


def test_done_event_carries_summary(passages):
    events = _events_from(synthesize_stream("query", passages, [10, 20]))
    done = events[-1]
    assert done["event"] == "done"
    assert done["data"]["chunks"] >= 1
    assert done["data"]["body_length"] > 0


def test_fixture_invalid_emits_out_of_allowed_marker(monkeypatch, passages):
    monkeypatch.setenv("SYNTHESIZER_FIXTURE", "invalid")
    events = _events_from(synthesize_stream("query", passages, [10, 20]))
    citations = [e for e in events if e["event"] == "citation"]
    invalid = [c for c in citations if not c["data"]["valid"]]
    assert len(invalid) >= 1, "fixture=invalid should emit at least one out-of-allowed marker"


def test_no_passages_still_emits_intro_and_done():
    events = _events_from(synthesize_stream("query", [], []))
    names = [e["event"] for e in events]
    assert names == ["chunk", "done"]
