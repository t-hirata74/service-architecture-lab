"""calendly ai-worker /recommend_slots エンドポイント。

ローカル完結方針 + 学習目的に従い、ML を持たず deterministic mock で「候補スロットの推薦スコア」を返す。
入力 (host_id + invitee_email + slot start_at_utc) に対して sha256 ベースで決定的にスコアを生成する。
同じ入力には常に同じスコアが返るので、E2E テスト / Rails 側のキャッシュとも整合する。
"""

import hashlib
from typing import List

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from app.security import verify_internal_token

router = APIRouter()


class CandidateSlot(BaseModel):
    start_at_utc: str = Field(min_length=1)
    end_at_utc: str = Field(min_length=1)


class RecommendRequest(BaseModel):
    host_id: int
    invitee_email: str = Field(min_length=1)
    candidates: List[CandidateSlot] = Field(min_length=1, max_length=200)


class ScoredSlot(BaseModel):
    start_at_utc: str
    end_at_utc: str
    score: float
    reason_code: str


class RecommendResponse(BaseModel):
    recommended: List[ScoredSlot]
    input_hash: str


_REASON_CODES = ("morning_focus", "after_lunch", "end_of_day", "midweek_buffer")


def _score_for(seed: str) -> tuple[float, str]:
    digest = hashlib.sha256(seed.encode()).hexdigest()
    # 0〜1 の決定的スコア
    score = int(digest[:6], 16) / 0xFFFFFF
    reason = _REASON_CODES[int(digest[6:8], 16) % len(_REASON_CODES)]
    return round(score, 4), reason


@router.post("/recommend_slots", dependencies=[Depends(verify_internal_token)])
async def recommend_slots(payload: RecommendRequest) -> RecommendResponse:
    seeds = []
    scored: List[ScoredSlot] = []
    for cand in payload.candidates:
        seed = f"host={payload.host_id};email={payload.invitee_email};start={cand.start_at_utc}"
        seeds.append(seed)
        score, reason = _score_for(seed)
        scored.append(
            ScoredSlot(
                start_at_utc=cand.start_at_utc,
                end_at_utc=cand.end_at_utc,
                score=score,
                reason_code=reason,
            )
        )

    # スコア降順でソートし、上位 5 件 (or 候補数のうち少ない方) を返す
    scored.sort(key=lambda s: s.score, reverse=True)
    recommended = scored[:5]

    overall_hash = hashlib.sha256("\n".join(seeds).encode()).hexdigest()
    return RecommendResponse(recommended=recommended, input_hash=overall_hash)
