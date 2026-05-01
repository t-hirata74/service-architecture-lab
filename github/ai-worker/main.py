"""ai-worker: GitHub 風プロジェクトの AI 処理（モック）レイヤ。

実 LLM は呼び出さず、決定論的なロジックで以下を返す:

- POST /review        : PR の AI レビューコメント
- POST /code-summary  : Issue / PR 説明の要約
- POST /check/run     : CI チェックのモック実行 → backend `/internal/commit_checks` に POST

本番化するなら各関数を実 LLM / コードレビュー SaaS 呼び出しに差し替える想定。
"""
from __future__ import annotations

import hashlib
import os
import re
from typing import Literal

import httpx
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

app = FastAPI(title="github-ai-worker", version="0.1.0")

BACKEND_URL = os.getenv("BACKEND_URL", "http://localhost:3030")
INTERNAL_TOKEN = os.getenv("INTERNAL_INGRESS_TOKEN", "dev-internal-token")


# ---- Models ----------------------------------------------------------------

class ReviewRequest(BaseModel):
    pull_request_number: int
    title: str
    body: str = ""
    diff: str = Field("", description="モック diff。実 git は扱わない")


class ReviewResponse(BaseModel):
    pull_request_number: int
    summary: str
    findings: list[str]


class CodeSummaryRequest(BaseModel):
    body: str = Field(..., min_length=1, max_length=20000)


class CodeSummaryResponse(BaseModel):
    summary: str


class CheckRunRequest(BaseModel):
    owner: str
    name: str
    head_sha: str
    check_name: str
    # 結果を強制したい時に指定（テスト用）
    force_state: Literal["success", "failure", "error"] | None = None


class CheckRunResponse(BaseModel):
    owner: str
    name: str
    head_sha: str
    check_name: str
    state: str
    output: str


# ---- Endpoints -------------------------------------------------------------

@app.get("/health")
def health() -> dict:
    return {"status": "ok", "service": "github-ai-worker"}


@app.post("/review", response_model=ReviewResponse)
def review(req: ReviewRequest) -> ReviewResponse:
    findings: list[str] = []
    body_text = f"{req.title}\n{req.body}\n{req.diff}"

    if re.search(r"TODO|FIXME", body_text, flags=re.IGNORECASE):
        findings.append("TODO/FIXME が残っています。リリース前に解消を検討してください。")
    if re.search(r"\bprint\(|console\.log\(", body_text):
        findings.append("デバッグ出力が含まれている可能性があります。")
    if len(req.title.strip()) < 5:
        findings.append("タイトルが短すぎる可能性があります（5 文字以上を推奨）。")
    if not findings:
        findings.append("特に懸念点は見つかりませんでした (mock)。")

    return ReviewResponse(
        pull_request_number=req.pull_request_number,
        summary=f"#{req.pull_request_number}: {req.title} (mock review)",
        findings=findings,
    )


@app.post("/code-summary", response_model=CodeSummaryResponse)
def code_summary(req: CodeSummaryRequest) -> CodeSummaryResponse:
    text = re.sub(r"\s+", " ", req.body).strip()
    head = text[:140]
    suffix = "…" if len(text) > 140 else ""
    return CodeSummaryResponse(summary=f"{head}{suffix}")


@app.post("/check/run", response_model=CheckRunResponse)
def check_run(req: CheckRunRequest) -> CheckRunResponse:
    # 決定論モック: head_sha を元にハッシュして state を決める。
    # force_state が指定されればそれを優先 (テスト用)。
    if req.force_state:
        state = req.force_state
    else:
        digest = int(hashlib.sha256(f"{req.head_sha}:{req.check_name}".encode()).hexdigest(), 16)
        state = "success" if digest % 5 != 0 else "failure"

    output = f"mock check '{req.check_name}' for {req.head_sha[:7]} -> {state}"

    # backend の internal ingress に upsert を投げる
    payload = {
        "owner": req.owner,
        "name": req.name,
        "head_sha": req.head_sha,
        "check_name": req.check_name,
        "state": state,
        "output": output,
    }
    try:
        with httpx.Client(timeout=5.0) as client:
            resp = client.post(
                f"{BACKEND_URL}/internal/commit_checks",
                json=payload,
                headers={"X-Internal-Token": INTERNAL_TOKEN},
            )
            resp.raise_for_status()
    except httpx.HTTPError as e:
        raise HTTPException(status_code=502, detail=f"backend ingress failed: {e}") from e

    return CheckRunResponse(
        owner=req.owner,
        name=req.name,
        head_sha=req.head_sha,
        check_name=req.check_name,
        state=state,
        output=output,
    )
