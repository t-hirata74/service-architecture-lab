"""zoom ai-worker FastAPI app。

ローカル完結方針につき LLM 本体は持たず、deterministic な mock のみ。
- POST /summarize: 会議の transcript_seed から deterministic な要約を返す (ADR 0003)
"""

from fastapi import FastAPI

from app.api import router as summarize_router

app = FastAPI(title="zoom-ai-worker")


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}


app.include_router(summarize_router)
