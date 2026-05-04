"""ai-worker FastAPI app。ローカル完結方針につき LLM 本体は持たず、deterministic な mock のみ。"""

from fastapi import FastAPI

from app.api import router as enrichment_router

app = FastAPI(title="shopify-ai-worker")


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}


app.include_router(enrichment_router)
