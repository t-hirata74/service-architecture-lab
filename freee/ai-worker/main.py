"""freee ai-worker (FastAPI).

freee/docs/architecture.md の通り、deterministic な mock を提供する
(実 ML / 外部 API は使わない — CLAUDE.md「ローカル完結方針」):

- POST /suggest-account : 取引摘要から勘定科目をキーワードヒューリスティックで提案する

DB アクセスは持たない。backend (Hono) が body で description を渡す。
backend → ai-worker は同期 REST + 共有トークン (X-Internal-Token)。
backend 側は不通/エラーを graceful degradation で吸収する (提案なしでも記帳は通す)。
ai-worker は会計の真実を持たない (記帳はユーザー確定後に backend が行う)。

互換性: PEP 604 を避け typing.Optional/List を使い Python 3.9+ で動く (他プロジェクトと同方針)。
"""
from __future__ import annotations

import os
import secrets
from typing import List, Optional, Tuple

from fastapi import Depends, FastAPI, Header, HTTPException
from pydantic import BaseModel

app = FastAPI(title="freee-ai-worker", version="0.1.0")

INTERNAL_TOKEN = os.environ.get("INTERNAL_TOKEN", "dev-internal-token")

# 摘要に含まれるキーワード → 勘定科目名。先頭からマッチ優先 (deterministic)。
RULES: List[Tuple[str, str]] = [
    ("交通", "旅費交通費"),
    ("電車", "旅費交通費"),
    ("タクシー", "旅費交通費"),
    ("会議", "会議費"),
    ("打合せ", "会議費"),
    ("家賃", "地代家賃"),
    ("通信", "通信費"),
    ("ソフト", "通信費"),
    ("売上", "売上高"),
    ("請求", "売上高"),
    ("消耗品", "消耗品費"),
]
FALLBACK = "雑費"


def require_internal_token(
    x_internal_token: Optional[str] = Header(default=None, alias="X-Internal-Token"),
) -> None:
    if x_internal_token is None or not secrets.compare_digest(x_internal_token, INTERNAL_TOKEN):
        raise HTTPException(status_code=401, detail="invalid internal token")


class SuggestRequest(BaseModel):
    description: str


class SuggestResponse(BaseModel):
    account_name: str
    confidence: float


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}


@app.post("/suggest-account", response_model=SuggestResponse, dependencies=[Depends(require_internal_token)])
def suggest_account(req: SuggestRequest) -> SuggestResponse:
    text = req.description or ""
    for keyword, account_name in RULES:
        if keyword in text:
            return SuggestResponse(account_name=account_name, confidence=0.9)
    return SuggestResponse(account_name=FALLBACK, confidence=0.3)
