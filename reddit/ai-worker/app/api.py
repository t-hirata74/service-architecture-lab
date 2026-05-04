"""Mock enrichment endpoints for backend → ai-worker.

CLAUDE.md「ローカル完結」方針に従い、外部 LLM は使わずハッシュ + 簡易 NLP で
deterministic な結果を返す。perplexity / discord / instagram と同パターン。

すべて X-Internal-Token を要求する (defense-in-depth)。
"""

from __future__ import annotations

import hashlib
import secrets
from collections import Counter

from fastapi import APIRouter, Depends, Header, HTTPException
from pydantic import BaseModel, Field

from app.config import get_settings


def require_internal_token(
    x_internal_token: str | None = Header(default=None, alias="X-Internal-Token"),
) -> None:
    expected = get_settings().internal_token
    if x_internal_token is None or not secrets.compare_digest(x_internal_token, expected):
        raise HTTPException(status_code=401, detail="invalid internal token")


router = APIRouter(dependencies=[Depends(require_internal_token)])


# ── /summarize ──────────────────────────────────────────────────────────────


class SummarizeRequest(BaseModel):
    title: str = Field(min_length=1, max_length=255)
    body: str = Field(default="", max_length=40000)


class SummarizeResponse(BaseModel):
    summary: str
    keywords: list[str]


_STOP = {
    "the", "a", "an", "is", "are", "was", "were", "to", "of", "in", "on", "at",
    "for", "and", "or", "but", "with", "this", "that", "it", "be", "as", "by",
    "i", "you", "we", "they", "he", "she", "my", "your", "our", "their",
}


def _summarize(title: str, body: str) -> SummarizeResponse:
    words: Counter[str] = Counter()
    for raw in (title + " " + body).split():
        w = "".join(ch for ch in raw.lower() if ch.isalnum())
        if len(w) >= 3 and w not in _STOP:
            words[w] += 1
    keywords = [w for w, _ in words.most_common(5)]
    if keywords:
        summary = f"TL;DR: {title} — keywords: {', '.join(keywords)}."
    else:
        summary = f"TL;DR: {title}"
    return SummarizeResponse(summary=summary, keywords=keywords)


@router.post("/summarize", response_model=SummarizeResponse)
def summarize(req: SummarizeRequest) -> SummarizeResponse:
    return _summarize(req.title, req.body)


# ── /related ────────────────────────────────────────────────────────────────


class RelatedRequest(BaseModel):
    subreddit: str = Field(min_length=2, max_length=64)


class RelatedResponse(BaseModel):
    related: list[str]


# 静的なシード集合。本物の Reddit なら共起グラフから出すが、ローカル完結 mock。
_SEED = [
    "python", "programming", "learnpython", "django", "fastapi", "rust",
    "golang", "typescript", "javascript", "react", "machinelearning", "datascience",
]


def _related(name: str) -> RelatedResponse:
    digest = hashlib.sha256(name.lower().encode("utf-8")).digest()
    pool = [s for s in _SEED if s.lower() != name.lower()]
    out: list[str] = []
    for i in range(3):
        idx = digest[i] % len(pool)
        candidate = pool[idx]
        if candidate not in out:
            out.append(candidate)
    return RelatedResponse(related=out)


@router.post("/related", response_model=RelatedResponse)
def related(req: RelatedRequest) -> RelatedResponse:
    return _related(req.subreddit)


# ── /spam-check ─────────────────────────────────────────────────────────────


class SpamCheckRequest(BaseModel):
    body: str = Field(min_length=1, max_length=40000)


class SpamCheckResponse(BaseModel):
    flagged: bool
    score: float = Field(ge=0.0, le=1.0)
    reasons: list[str]


_BANNED_TERMS = ("spam", "scam", "phish", "buy now", "click here", "free money")


def _spam_check(body: str) -> SpamCheckResponse:
    text = body.lower()
    reasons: list[str] = []
    keyword_hits = sum(1 for term in _BANNED_TERMS if term in text)
    if keyword_hits:
        reasons.append(f"matched_{keyword_hits}_banned_terms")

    digest = hashlib.sha256(body.encode("utf-8")).digest()
    base = int.from_bytes(digest[:4], "big") / 0xFFFFFFFF
    score = round(min(1.0, base * 0.5 + keyword_hits * 0.3), 3)
    flagged = keyword_hits > 0
    return SpamCheckResponse(flagged=flagged, score=score, reasons=reasons)


@router.post("/spam-check", response_model=SpamCheckResponse)
def spam_check(req: SpamCheckRequest) -> SpamCheckResponse:
    return _spam_check(req.body)
