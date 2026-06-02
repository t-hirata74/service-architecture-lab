"""uber ai-worker (FastAPI).

uber/docs/architecture.md / ADR 0004 の通り、ai-worker は以下 2 経路を deterministic な
mock で提供する (外部 ML / 地図 API は使わない — CLAUDE.md「ローカル完結方針」):

- POST /eta             : pickup/dropoff 座標から到着見込み秒 + 概算距離 (haversine)
- POST /demand-forecast : H3 cell の需要指数 + surge 係数 (cell をハッシュした deterministic 値)

DB アクセスは持たない。backend (Go dispatch) が body で必要な値を渡す。
backend → ai-worker は同期 REST + 共有トークン (X-Internal-Token) で、defense-in-depth。
backend 側は ai-worker 不在/遅延/エラーを graceful degradation で吸収する (ADR 0004)。

互換性: 評価される型ヒントに PEP 604 (`X | None`) を使わず typing.Optional を使うことで
Python 3.9+ でも動く (CI は 3.12)。
"""
from __future__ import annotations

import hashlib
import math
import os
import secrets
from typing import Optional

from fastapi import Depends, FastAPI, Header, HTTPException
from pydantic import BaseModel, Field

app = FastAPI(title="uber-ai-worker", version="0.1.0")


# ─── shared secret ──────────────────────────────────────────────────────────
# Go dispatch 経由のみ ai-worker を呼ぶ前提。defense-in-depth として
# X-Internal-Token を要求する (discord ai-worker と同形)。
# backend 側の AI_INTERNAL_TOKEN と一致させる。
INTERNAL_TOKEN = os.environ.get("INTERNAL_TOKEN", "dev-internal-token")

# 都市内走行を仮定した平均速度 (m/s)。30 km/h ≒ 8.33 m/s。
_AVG_SPEED_MPS = 8.33
# マッチ + 乗車前の固定オーバーヘッド秒。
_BASE_OVERHEAD_S = 60


def require_internal_token(
    x_internal_token: Optional[str] = Header(default=None, alias="X-Internal-Token"),
) -> None:
    if x_internal_token is None or not secrets.compare_digest(
        x_internal_token, INTERNAL_TOKEN
    ):
        raise HTTPException(status_code=401, detail="invalid internal token")


# ─── /health ──────────────────────────────────────────────────────────────--


@app.get("/health")
def health() -> dict:
    return {"ok": True}


# ─── /eta ─────────────────────────────────────────────────────────────────--


class ETARequest(BaseModel):
    pickup_lat: float = Field(ge=-90.0, le=90.0)
    pickup_lng: float = Field(ge=-180.0, le=180.0)
    dropoff_lat: float = Field(ge=-90.0, le=90.0)
    dropoff_lng: float = Field(ge=-180.0, le=180.0)


class ETAResponse(BaseModel):
    eta_seconds: int
    distance_meters: int


def _haversine_meters(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """2 点間の大圏距離 (m)。地図 API を使わない deterministic な距離計算。"""
    r = 6_371_000.0  # 地球半径 (m)
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlmb = math.radians(lng2 - lng1)
    a = (
        math.sin(dphi / 2) ** 2
        + math.cos(p1) * math.cos(p2) * math.sin(dlmb / 2) ** 2
    )
    return 2 * r * math.asin(math.sqrt(a))


def _eta(req: ETARequest) -> ETAResponse:
    dist = _haversine_meters(
        req.pickup_lat, req.pickup_lng, req.dropoff_lat, req.dropoff_lng
    )
    eta = _BASE_OVERHEAD_S + dist / _AVG_SPEED_MPS
    return ETAResponse(eta_seconds=int(round(eta)), distance_meters=int(round(dist)))


@app.post(
    "/eta",
    response_model=ETAResponse,
    dependencies=[Depends(require_internal_token)],
)
def eta(req: ETARequest) -> ETAResponse:
    return _eta(req)


# ─── /demand-forecast ───────────────────────────────────────────────────────


class DemandForecastRequest(BaseModel):
    h3_cell: str = Field(min_length=1, max_length=16)


class DemandForecastResponse(BaseModel):
    h3_cell: str
    demand_index: float = Field(ge=0.0, le=1.0)
    surge_multiplier: float = Field(ge=1.0, le=2.0)


def _demand_forecast(cell: str) -> DemandForecastResponse:
    # cell をハッシュした deterministic な需要指数 0..1。
    # 同じ cell には常に同じ値を返す (mock だが安定)。
    digest = hashlib.sha256(cell.encode("utf-8")).digest()
    demand = int.from_bytes(digest[:4], "big") / 0xFFFFFFFF  # 0..1
    demand = round(demand, 3)
    # surge は需要に比例して 1.0..2.0。0.1 刻みに丸めて UI で扱いやすく。
    surge = round(1.0 + demand, 1)
    return DemandForecastResponse(
        h3_cell=cell, demand_index=demand, surge_multiplier=surge
    )


@app.post(
    "/demand-forecast",
    response_model=DemandForecastResponse,
    dependencies=[Depends(require_internal_token)],
)
def demand_forecast(req: DemandForecastRequest) -> DemandForecastResponse:
    return _demand_forecast(req.h3_cell)
