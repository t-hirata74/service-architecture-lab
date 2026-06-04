"""datadog ai-worker (FastAPI).

datadog/docs/architecture.md / ADR 0004 の通り、deterministic な mock を提供する
(実 ML / 外部 API は使わない — CLAUDE.md「ローカル完結方針」):

- POST /detect-anomaly : 点列の z-score 異常検知 + 動的閾値 (mean + k*std)
- POST /forecast       : 最小二乗線形回帰による短期予測

DB アクセスは持たない。backend (Go) が body で点列を渡す。
backend → ai-worker は同期 REST + 共有トークン (X-Internal-Token)。
backend 側 (alert engine) は ai-worker 不通/エラーを graceful degradation で吸収し、
静的閾値で評価を継続する (ADR 0004)。

互換性: PEP 604 を避け typing.Optional/List を使い Python 3.9+ で動く (uber/figma と同方針)。
"""
from __future__ import annotations

import math
import os
import secrets
from typing import List, Optional

from fastapi import Depends, FastAPI, Header, HTTPException
from pydantic import BaseModel, Field

app = FastAPI(title="datadog-ai-worker", version="0.1.0")

INTERNAL_TOKEN = os.environ.get("INTERNAL_TOKEN", "dev-internal-token")


def require_internal_token(
    x_internal_token: Optional[str] = Header(default=None, alias="X-Internal-Token"),
) -> None:
    if x_internal_token is None or not secrets.compare_digest(x_internal_token, INTERNAL_TOKEN):
        raise HTTPException(status_code=401, detail="invalid internal token")


class Point(BaseModel):
    ts: Optional[int] = None
    value: float


# ─── /health ──────────────────────────────────────────────────────────────--


@app.get("/health")
def health() -> dict:
    return {"ok": True}


# ─── /detect-anomaly ──────────────────────────────────────────────────────--


class AnomalyRequest(BaseModel):
    points: List[Point]
    k: float = Field(default=3.0, ge=0.0)  # 何σを異常とみなすか


class AnomalyOut(BaseModel):
    index: int
    value: float
    score: float


class AnomalyResponse(BaseModel):
    mean: float
    std: float
    threshold: float  # mean + k*std (動的上限閾値)
    anomalies: List[AnomalyOut]


def _detect(req: AnomalyRequest) -> AnomalyResponse:
    vals = [p.value for p in req.points]
    n = len(vals)
    if n == 0:
        return AnomalyResponse(mean=0.0, std=0.0, threshold=0.0, anomalies=[])
    mean = sum(vals) / n
    var = sum((v - mean) ** 2 for v in vals) / n
    std = math.sqrt(var)
    threshold = mean + req.k * std
    anomalies: List[AnomalyOut] = []
    if std > 0:
        for i, v in enumerate(vals):
            score = (v - mean) / std
            if abs(score) > req.k:
                anomalies.append(AnomalyOut(index=i, value=v, score=round(score, 4)))
    return AnomalyResponse(mean=round(mean, 6), std=round(std, 6), threshold=round(threshold, 6), anomalies=anomalies)


@app.post("/detect-anomaly", response_model=AnomalyResponse, dependencies=[Depends(require_internal_token)])
def detect_anomaly(req: AnomalyRequest) -> AnomalyResponse:
    return _detect(req)


# ─── /forecast ──────────────────────────────────────────────────────────────


class ForecastRequest(BaseModel):
    points: List[Point]
    horizon: int = Field(default=3, ge=1, le=100)


class ForecastResponse(BaseModel):
    slope: float
    intercept: float
    forecast: List[float]


def _forecast(req: ForecastRequest) -> ForecastResponse:
    vals = [p.value for p in req.points]
    n = len(vals)
    if n < 2:
        last = vals[-1] if vals else 0.0
        return ForecastResponse(slope=0.0, intercept=last, forecast=[last] * req.horizon)
    # x = 0..n-1 に対する最小二乗線形回帰。
    xs = list(range(n))
    mx = sum(xs) / n
    my = sum(vals) / n
    denom = sum((x - mx) ** 2 for x in xs)
    slope = 0.0 if denom == 0 else sum((xs[i] - mx) * (vals[i] - my) for i in range(n)) / denom
    intercept = my - slope * mx
    forecast = [round(slope * (n + h) + intercept, 6) for h in range(req.horizon)]
    return ForecastResponse(slope=round(slope, 6), intercept=round(intercept, 6), forecast=forecast)


@app.post("/forecast", response_model=ForecastResponse, dependencies=[Depends(require_internal_token)])
def forecast(req: ForecastRequest) -> ForecastResponse:
    return _forecast(req)
