"""Discord ai-worker (FastAPI).

discord/docs/architecture.md の通り、ai-worker は以下 2 経路を mock 提供する:
- /summarize : チャンネル直近メッセージの要約 mock
- /moderate  : メッセージ本文のスパム / NSFW スコア mock

外部 LLM / NSFW model は使用しない (CLAUDE.md「ローカル完結方針」)。
DB アクセスは持たない (要約対象メッセージは Go gateway が body で渡す)。
"""
from __future__ import annotations

import hashlib
import os
from collections import Counter

from fastapi import Depends, FastAPI, Header, HTTPException
from pydantic import BaseModel, Field

app = FastAPI(title="discord-ai-worker", version="0.1.0")


# ─── shared secret ────────────────────────────────────────────────────────────
# Go gateway 経由のみ ai-worker を呼ぶ前提。defense-in-depth として
# X-Internal-Token を要求する。
INTERNAL_TOKEN = os.environ.get("INTERNAL_TOKEN", "dev-internal-token")


def require_internal_token(
    x_internal_token: str | None = Header(default=None, alias="X-Internal-Token"),
) -> None:
    if x_internal_token != INTERNAL_TOKEN:
        raise HTTPException(status_code=401, detail="invalid internal token")


# ─── /health ─────────────────────────────────────────────────────────────────


@app.get("/health")
def health() -> dict:
    return {"ok": True}


# ─── /summarize ──────────────────────────────────────────────────────────────


class SummarizeMessage(BaseModel):
    username: str
    body: str


class SummarizeRequest(BaseModel):
    messages: list[SummarizeMessage] = Field(default_factory=list)


class SummarizeResponse(BaseModel):
    summary: str
    message_count: int
    top_speakers: list[str]


_STOP = {
    "the", "a", "an", "is", "are", "was", "were", "to", "of", "in", "on", "at",
    "for", "and", "or", "but", "with", "this", "that", "it", "be", "as", "by",
    "i", "you", "we", "they", "he", "she", "my", "your", "our", "their",
}


def _summarize(messages: list[SummarizeMessage]) -> SummarizeResponse:
    if not messages:
        return SummarizeResponse(summary="(no messages)", message_count=0, top_speakers=[])

    speaker_counter: Counter[str] = Counter(m.username for m in messages)
    top_speakers = [name for name, _ in speaker_counter.most_common(3)]

    word_counter: Counter[str] = Counter()
    for m in messages:
        for raw in m.body.split():
            w = "".join(ch for ch in raw.lower() if ch.isalnum())
            if len(w) >= 3 and w not in _STOP:
                word_counter[w] += 1
    top_words = [w for w, _ in word_counter.most_common(5)]

    if top_words:
        topics = ", ".join(top_words)
    else:
        topics = "(no topical words)"
    summary = (
        f"{len(messages)} messages from {len(speaker_counter)} speakers "
        f"(top: {', '.join(top_speakers)}). Topics: {topics}."
    )
    return SummarizeResponse(
        summary=summary,
        message_count=len(messages),
        top_speakers=top_speakers,
    )


@app.post(
    "/summarize",
    response_model=SummarizeResponse,
    dependencies=[Depends(require_internal_token)],
)
def summarize(req: SummarizeRequest) -> SummarizeResponse:
    return _summarize(req.messages)


# ─── /moderate ────────────────────────────────────────────────────────────────


class ModerateRequest(BaseModel):
    body: str


class ModerateResponse(BaseModel):
    flagged: bool
    score: float = Field(ge=0.0, le=1.0)
    reasons: list[str]


_BANNED_TERMS = ("spam", "scam", "phish", "nsfw", "abuse")


def _moderate(body: str) -> ModerateResponse:
    text = body.lower()
    reasons: list[str] = []
    keyword_hits = sum(1 for term in _BANNED_TERMS if term in text)
    if keyword_hits:
        reasons.append(f"matched_{keyword_hits}_banned_terms")

    # deterministic 0.0..1.0 score from SHA-256 first 4 bytes
    digest = hashlib.sha256(body.encode("utf-8")).digest()
    base = int.from_bytes(digest[:4], "big") / 0xFFFFFFFF  # 0..1
    score = min(1.0, base * 0.5 + keyword_hits * 0.25)
    score = round(score, 3)

    if not reasons and score >= 0.85:
        reasons.append("hash_high_score")

    flagged = score >= 0.7 or keyword_hits > 0
    return ModerateResponse(flagged=flagged, score=score, reasons=reasons)


@app.post(
    "/moderate",
    response_model=ModerateResponse,
    dependencies=[Depends(require_internal_token)],
)
def moderate(req: ModerateRequest) -> ModerateResponse:
    return _moderate(req.body)
