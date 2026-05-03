"""Instagram ai-worker (FastAPI).

ADR 0001 (instagram/docs/adr) の通り、ai-worker は MySQL 読み専接続のみ。
- /recommend : Discovery feed mock。フォローしていないユーザの直近投稿を返す
- /tags      : 画像タグ抽出 mock。image_url の SHA-256 から deterministic に決める
- /health    : 疎通確認

外部 LLM / 画像認識 API は使用しない (CLAUDE.md「ローカル完結方針」)。
"""
from __future__ import annotations

import hashlib
import os
from typing import Iterable

from fastapi import Depends, FastAPI
from pydantic import BaseModel, Field
from sqlalchemy import Engine, create_engine, text


def _build_engine() -> Engine:
    url = os.environ.get(
        "DATABASE_URL",
        "mysql+pymysql://instagram:instagram@127.0.0.1:3311/instagram_development",
    )
    return create_engine(url, pool_pre_ping=True, pool_recycle=300, future=True)


_engine: Engine | None = None


def get_engine() -> Engine:
    """FastAPI Depends 用。テスト時は app.dependency_overrides で差し替え可能。"""
    global _engine
    if _engine is None:
        _engine = _build_engine()
    return _engine


app = FastAPI(title="instagram-ai-worker", version="0.1.0")


# ─── /health ─────────────────────────────────────────────────────────────────


@app.get("/health")
def health() -> dict:
    return {"ok": True}


# ─── /recommend ───────────────────────────────────────────────────────────────


class RecommendRequest(BaseModel):
    user_id: int
    top_k: int = Field(default=20, ge=1, le=100)


class RecommendResponse(BaseModel):
    post_ids: list[int]


_RECOMMEND_SQL = text(
    """
    SELECT p.id
    FROM posts p
    WHERE p.deleted_at IS NULL
      AND p.user_id <> :user_id
      AND p.user_id NOT IN (
        SELECT followee_id FROM follow_edges WHERE follower_id = :user_id
      )
    ORDER BY p.created_at DESC, p.id DESC
    LIMIT :limit
    """
)


@app.post("/recommend", response_model=RecommendResponse)
def recommend(req: RecommendRequest, engine: Engine = Depends(get_engine)) -> RecommendResponse:
    with engine.connect() as conn:
        rows = conn.execute(
            _RECOMMEND_SQL, {"user_id": req.user_id, "limit": req.top_k}
        ).fetchall()
    return RecommendResponse(post_ids=[r[0] for r in rows])


# ─── /tags ────────────────────────────────────────────────────────────────────


_TAG_POOL = (
    "nature",
    "food",
    "portrait",
    "city",
    "art",
    "travel",
    "fitness",
    "pets",
    "fashion",
    "tech",
    "music",
    "coffee",
)


class TagsRequest(BaseModel):
    image_url: str


class TagsResponse(BaseModel):
    tags: list[str]


def _deterministic_tags(image_url: str) -> list[str]:
    digest = hashlib.sha256(image_url.encode("utf-8")).digest()
    n = 3 + (digest[0] % 3)  # 3 〜 5 個
    seen: list[str] = []
    for i in range(n + 4):  # 重複を避けるための余裕
        if len(seen) >= n:
            break
        tag = _TAG_POOL[digest[i] % len(_TAG_POOL)]
        if tag not in seen:
            seen.append(tag)
    return seen


@app.post("/tags", response_model=TagsResponse)
def tags(req: TagsRequest) -> TagsResponse:
    return TagsResponse(tags=_deterministic_tags(req.image_url))
