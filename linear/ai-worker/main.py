"""linear ai-worker (FastAPI).

linear/docs/architecture.md の通り、deterministic な mock を提供する
(実 ML / 外部 API は使わない — CLAUDE.md「ローカル完結方針」):

- POST /triage     : キーワードヒューリスティックで priority / labels / reason を提案
- POST /duplicates : タイトルのトークン Jaccard 類似で重複候補 issue を返す

DB アクセスは持たない。backend (NestJS AiService) が body で title / candidates を渡す。
backend → ai-worker は同期 REST + 共有トークン (X-Internal-Token)。
backend 側は不通/エラーを graceful degradation (available=false) で吸収する。

priority の並びは shared/schema/entities.ts と同じ: 0=none 1=urgent 2=high 3=medium 4=low。

互換性: PEP 604 を避け typing.Optional/List を使い Python 3.9+ で動く (他プロジェクトと同方針)。
"""
from __future__ import annotations

import os
import re
import secrets
from typing import List, Optional, Set, Tuple

from fastapi import Depends, FastAPI, Header, HTTPException
from pydantic import BaseModel

app = FastAPI(title="linear-ai-worker", version="0.1.0")

INTERNAL_TOKEN = os.environ.get("INTERNAL_TOKEN", "dev-internal-token")


def require_internal_token(
    x_internal_token: Optional[str] = Header(default=None, alias="X-Internal-Token"),
) -> None:
    if x_internal_token is None or not secrets.compare_digest(x_internal_token, INTERNAL_TOKEN):
        raise HTTPException(status_code=401, detail="invalid internal token")


# ─── /health ──────────────────────────────────────────────────────────────--


@app.get("/health")
def health() -> dict:
    return {"ok": True}


# ─── /triage ──────────────────────────────────────────────────────────────--

# (priority, label, keywords) — 上から順に最初にヒットした行が priority を決める
_RULES: List[Tuple[int, str, Tuple[str, ...]]] = [
    (1, "bug", ("crash", "outage", "data loss", "security", "vulnerability", "落ちる", "停止")),
    (2, "bug", ("bug", "error", "broken", "fail", "exception", "バグ", "エラー", "壊れ")),
    (2, "performance", ("slow", "performance", "latency", "timeout", "遅い", "重い")),
    (4, "docs", ("typo", "docs", "documentation", "readme", "ドキュメント", "誤字")),
    (3, "feature", ("feature", "add ", "support", "新機能", "追加", "対応")),
]
_DEFAULT_PRIORITY = 3  # medium


class TriageRequest(BaseModel):
    title: str
    description: str = ""


class TriageOut(BaseModel):
    priority: int
    labels: List[str]
    reason: str


@app.post("/triage", dependencies=[Depends(require_internal_token)])
def triage(req: TriageRequest) -> TriageOut:
    text = f"{req.title} {req.description}".lower()
    priority: Optional[int] = None
    labels: List[str] = []
    matched: List[str] = []
    for rule_priority, label, keywords in _RULES:
        hits = [k for k in keywords if k in text]
        if not hits:
            continue
        if priority is None:
            priority = rule_priority
        if label not in labels:
            labels.append(label)
        matched.extend(hits)
    if priority is None:
        return TriageOut(
            priority=_DEFAULT_PRIORITY,
            labels=[],
            reason="no keyword matched; default to medium",
        )
    return TriageOut(
        priority=priority,
        labels=labels,
        reason="matched: " + ", ".join(sorted(set(matched))),
    )


# ─── /duplicates ──────────────────────────────────────────────────────────--

# stemming を持たないため活用形 (submit / submitting) は別トークンになる。
# その分を見込んで閾値はやや緩め (実測: ほぼ同文で ~0.43)
_DUP_THRESHOLD = 0.4
_MAX_DUPLICATES = 5


def _tokens(text: str) -> Set[str]:
    # 英数字の単語 + CJK は 1 文字単位 (簡易 bigram の代わり)
    return set(re.findall(r"[a-z0-9]+|[぀-ヿ一-鿿]", text.lower()))


def _jaccard(a: Set[str], b: Set[str]) -> float:
    if not a or not b:
        return 0.0
    return len(a & b) / len(a | b)


class Candidate(BaseModel):
    id: int
    title: str


class DuplicatesRequest(BaseModel):
    title: str
    candidates: List[Candidate] = []


class DuplicatesOut(BaseModel):
    duplicate_ids: List[int]


@app.post("/duplicates", dependencies=[Depends(require_internal_token)])
def duplicates(req: DuplicatesRequest) -> DuplicatesOut:
    base = _tokens(req.title)
    scored = [
        (c.id, _jaccard(base, _tokens(c.title)))
        for c in req.candidates
    ]
    hits = sorted(
        (s for s in scored if s[1] >= _DUP_THRESHOLD),
        key=lambda s: (-s[1], s[0]),
    )
    return DuplicatesOut(duplicate_ids=[issue_id for issue_id, _ in hits[:_MAX_DUPLICATES]])
