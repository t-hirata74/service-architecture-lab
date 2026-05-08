"""calendly ai-worker FastAPI app。

ローカル完結方針につき ML を持たず、deterministic な mock のみ。
- POST /recommend_slots: candidates の配列を受け取り、決定的なスコアを返す
"""

from fastapi import FastAPI

from app.api import router as recommend_router

app = FastAPI(title="calendly-ai-worker")


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}


app.include_router(recommend_router)
