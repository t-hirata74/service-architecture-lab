"""ai-worker FastAPI app + APScheduler.

ADR 0003: 60s 間隔で recompute_hot_scores を、nightly で reconcile_score を実行する。

テスト時は ``ENABLE_SCHEDULER=false`` にして scheduler を起動しない。
"""

from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from apscheduler.schedulers.asyncio import AsyncIOScheduler
from fastapi import FastAPI

from app.api import router as enrichment_router
from app.config import get_settings
from app.jobs import recompute_hot_scores, reconcile_score

logger = logging.getLogger("ai-worker")

_scheduler: AsyncIOScheduler | None = None


def _build_scheduler() -> AsyncIOScheduler:
    settings = get_settings()
    sched = AsyncIOScheduler()
    sched.add_job(
        recompute_hot_scores,
        "interval",
        seconds=settings.hot_recompute_interval_seconds,
        id="recompute_hot_scores",
        max_instances=1,
        coalesce=True,
    )
    sched.add_job(
        reconcile_score,
        "cron",
        hour=3,
        minute=0,
        id="reconcile_score",
        max_instances=1,
        coalesce=True,
    )
    return sched


@asynccontextmanager
async def lifespan(app: FastAPI):
    global _scheduler
    if get_settings().enable_scheduler:
        _scheduler = _build_scheduler()
        _scheduler.start()
        logger.info("scheduler started")
    yield
    if _scheduler is not None:
        _scheduler.shutdown(wait=False)


def create_app() -> FastAPI:
    app = FastAPI(title="reddit-ai-worker", version="0.1.0", lifespan=lifespan)
    app.include_router(enrichment_router)

    @app.get("/health")
    def health() -> dict:
        return {"ok": True}

    return app


app = create_app()
