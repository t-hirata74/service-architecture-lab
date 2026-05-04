"""ai-worker のエンリッチメント API (mock 実装)。

本リポはローカル完結方針につき LLM 本体は使わない。すべて deterministic に算出する mock。
"""

from __future__ import annotations

import hashlib
from typing import Any

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from app.security import verify_internal_token

router = APIRouter(dependencies=[Depends(verify_internal_token)])


class RecommendRequest(BaseModel):
    shop_id: int
    product_id: int
    candidate_product_ids: list[int] = Field(default_factory=list)
    limit: int = 5


class RecommendResponse(BaseModel):
    product_id: int
    related: list[int]


class SummarizeRequest(BaseModel):
    product_id: int
    review_count: int


class SummarizeResponse(BaseModel):
    product_id: int
    summary: str
    reviewed: int


class ForecastRequest(BaseModel):
    variant_id: int
    last_n_days_sales: list[int]


class ForecastResponse(BaseModel):
    variant_id: int
    forecast_units: int
    method: str = "moving_average_x1.2"


def _deterministic_pick(seed: int, candidates: list[int], limit: int) -> list[int]:
    """seed をハッシュに混ぜて、候補から limit 件を再現可能に並べ替えて返す。"""
    if not candidates:
        return []
    keyed = sorted(
        candidates,
        key=lambda c: hashlib.sha1(f"{seed}:{c}".encode()).hexdigest(),
    )
    return keyed[:limit]


@router.post("/recommend", response_model=RecommendResponse)
async def recommend(req: RecommendRequest) -> dict[str, Any]:
    others = [c for c in req.candidate_product_ids if c != req.product_id]
    return {"product_id": req.product_id, "related": _deterministic_pick(req.product_id, others, req.limit)}


@router.post("/summarize-reviews", response_model=SummarizeResponse)
async def summarize_reviews(req: SummarizeRequest) -> dict[str, Any]:
    if req.review_count == 0:
        summary = "No reviews yet."
    else:
        summary = f"{req.review_count} reviews summarized: customers generally rate this product well (mock)."
    return {"product_id": req.product_id, "summary": summary, "reviewed": req.review_count}


@router.post("/forecast-demand", response_model=ForecastResponse)
async def forecast_demand(req: ForecastRequest) -> dict[str, Any]:
    sales = req.last_n_days_sales or [0]
    avg = sum(sales) / len(sales)
    return {"variant_id": req.variant_id, "forecast_units": int(round(avg * 1.2))}
