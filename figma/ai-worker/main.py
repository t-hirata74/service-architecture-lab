"""figma ai-worker (FastAPI).

figma/docs/architecture.md / ADR 0003 の通り、ai-worker は以下を deterministic な
mock (実ジオメトリ計算) で提供する。外部 ML / LLM は使わない (CLAUDE.md「ローカル完結方針」):

- POST /auto-layout : 選択オブジェクトの整列・等間隔分配を実ジオメトリで計算
- POST /lint        : 重なり / グリッド外を検出し suggestion を返す

DB アクセスは持たない。backend (Rails) が body で必要な geometry を渡す。
backend → ai-worker は同期 REST + 共有トークン (X-Internal-Token) で defense-in-depth。
backend 側 (AiWorkerClient) は ai-worker 不在/遅延/エラーを graceful degradation で吸収する。

互換性: PEP 604 (`X | None`) を避け typing.Optional/List を使うことで Python 3.9+ でも動く
(uber ai-worker と同方針 / CI は 3.12 想定)。
"""
from __future__ import annotations

import os
import secrets
from typing import List, Optional

from fastapi import Depends, FastAPI, Header, HTTPException
from pydantic import BaseModel, Field

app = FastAPI(title="figma-ai-worker", version="0.1.0")

# backend (Rails) 経由のみ呼ぶ前提の共有シークレット (uber / discord ai-worker と同形)。
INTERNAL_TOKEN = os.environ.get("INTERNAL_TOKEN", "dev-internal-token")


def require_internal_token(
    x_internal_token: Optional[str] = Header(default=None, alias="X-Internal-Token"),
) -> None:
    if x_internal_token is None or not secrets.compare_digest(x_internal_token, INTERNAL_TOKEN):
        raise HTTPException(status_code=401, detail="invalid internal token")


# ─── models ─────────────────────────────────────────────────────────────────


class Obj(BaseModel):
    id: str
    x: float = 0.0
    y: float = 0.0
    w: float = 0.0
    h: float = 0.0


class Update(BaseModel):
    id: str
    x: float
    y: float


class AutoLayoutRequest(BaseModel):
    objects: List[Obj]
    mode: str = "align-left"


class AutoLayoutResponse(BaseModel):
    mode: str
    updates: List[Update]


class LintRequest(BaseModel):
    objects: List[Obj]
    grid: int = Field(default=8, ge=0)


# ─── /health ──────────────────────────────────────────────────────────────--


@app.get("/health")
def health() -> dict:
    return {"ok": True}


# ─── /auto-layout ─────────────────────────────────────────────────────────--

ALIGN_MODES = {"align-left", "align-right", "align-top", "align-bottom"}
DISTRIBUTE_MODES = {"distribute-h", "distribute-v"}


def _auto_layout(req: AutoLayoutRequest) -> AutoLayoutResponse:
    objs = req.objects
    if len(objs) < 2:
        return AutoLayoutResponse(mode=req.mode, updates=[])

    if req.mode == "align-left":
        t = min(o.x for o in objs)
        updates = [Update(id=o.id, x=t, y=o.y) for o in objs]
    elif req.mode == "align-right":
        t = max(o.x + o.w for o in objs)
        updates = [Update(id=o.id, x=t - o.w, y=o.y) for o in objs]
    elif req.mode == "align-top":
        t = min(o.y for o in objs)
        updates = [Update(id=o.id, x=o.x, y=t) for o in objs]
    elif req.mode == "align-bottom":
        t = max(o.y + o.h for o in objs)
        updates = [Update(id=o.id, x=o.x, y=t - o.h) for o in objs]
    elif req.mode in DISTRIBUTE_MODES:
        updates = _distribute(objs, axis="x" if req.mode == "distribute-h" else "y")
    else:
        raise HTTPException(status_code=422, detail=f"unknown mode: {req.mode}")

    return AutoLayoutResponse(mode=req.mode, updates=updates)


def _distribute(objs: List[Obj], axis: str) -> List[Update]:
    # 端 2 つを固定し、間を等間隔 (端の間の合計余白を均等割り) にする。
    pos = (lambda o: o.x) if axis == "x" else (lambda o: o.y)
    size = (lambda o: o.w) if axis == "x" else (lambda o: o.h)
    ordered = sorted(objs, key=pos)
    if len(ordered) < 3:
        return [Update(id=o.id, x=o.x, y=o.y) for o in objs]  # 端しかない → no-op

    span = (pos(ordered[-1]) + size(ordered[-1])) - pos(ordered[0])
    gap = (span - sum(size(o) for o in ordered)) / (len(ordered) - 1)

    updates: List[Update] = []
    cursor = pos(ordered[0])
    for o in ordered:
        if axis == "x":
            updates.append(Update(id=o.id, x=round(cursor, 3), y=o.y))
        else:
            updates.append(Update(id=o.id, x=o.x, y=round(cursor, 3)))
        cursor += size(o) + gap
    return updates


@app.post("/auto-layout", response_model=AutoLayoutResponse, dependencies=[Depends(require_internal_token)])
def auto_layout(req: AutoLayoutRequest) -> AutoLayoutResponse:
    return _auto_layout(req)


# ─── /lint ──────────────────────────────────────────────────────────────────


def _overlap(a: Obj, b: Obj) -> bool:
    return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h


def _lint(req: LintRequest) -> dict:
    issues = []
    objs = req.objects
    grid = req.grid
    for i, o in enumerate(objs):
        if grid > 0 and (o.x % grid != 0 or o.y % grid != 0):
            issues.append({
                "object_id": o.id,
                "kind": "off_grid",
                "suggestion": {"x": round(o.x / grid) * grid, "y": round(o.y / grid) * grid},
            })
        for other in objs[i + 1:]:
            if _overlap(o, other):
                issues.append({"object_id": o.id, "kind": "overlap", "other_id": other.id})
    return {"issues": issues}


@app.post("/lint", dependencies=[Depends(require_internal_token)])
def lint(req: LintRequest) -> dict:
    return _lint(req)
