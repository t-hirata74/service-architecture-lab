"""Periodic jobs (ADR 0003 + ADR 0002).

- ``recompute_hot_scores``: 直近 N 日分の posts に対して Hot 式を計算し直して
  bulk UPDATE する。60s 間隔で APScheduler から呼ばれる。
- ``reconcile_score``: votes の SUM(value) を集計して posts.score / comments.score
  との drift を検出する。MVP ではログ出力のみ。
"""

from __future__ import annotations

import logging
from datetime import datetime, timedelta, timezone

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.db import get_sessionmaker
from app.ranking import hot_score

logger = logging.getLogger("ai-worker.jobs")


async def recompute_hot_scores(session: AsyncSession | None = None) -> int:
    """Returns the number of posts updated."""
    settings = get_settings()
    cutoff = datetime.now(timezone.utc).replace(tzinfo=None) - timedelta(
        days=settings.hot_recompute_window_days
    )

    if session is None:
        async with get_sessionmaker()() as s:
            return await _recompute(s, cutoff)
    return await _recompute(session, cutoff)


async def _recompute(session: AsyncSession, cutoff: datetime) -> int:
    rows = (
        await session.execute(
            text(
                "SELECT id, score, created_at FROM posts "
                "WHERE deleted_at IS NULL AND created_at > :cutoff"
            ),
            {"cutoff": cutoff},
        )
    ).all()
    if not rows:
        return 0

    now = datetime.now(timezone.utc).replace(tzinfo=None)
    payload = []
    for r in rows:
        created = r.created_at
        if isinstance(created, str):
            created = datetime.fromisoformat(created)
        payload.append({"id": r.id, "h": hot_score(r.score, created), "now": now})
    await session.execute(
        text(
            "UPDATE posts SET hot_score = :h, hot_recomputed_at = :now WHERE id = :id"
        ),
        payload,
    )
    await session.commit()
    logger.info("recompute_hot_scores: updated %d posts", len(payload))
    return len(payload)


async def reconcile_score(session: AsyncSession | None = None) -> dict[str, int]:
    """votes の SUM と posts/comments の score を比較し drift を検出。

    Returns: {"posts_drift": N, "comments_drift": M}。
    drift は ログ出力のみ (MVP では自動修正しない)。
    """
    if session is None:
        async with get_sessionmaker()() as s:
            return await _reconcile(s)
    return await _reconcile(session)


async def _reconcile(session: AsyncSession) -> dict[str, int]:
    posts_drift = await _drift_for_target(session, "post", "posts")
    comments_drift = await _drift_for_target(session, "comment", "comments")
    if posts_drift or comments_drift:
        logger.warning(
            "reconcile_score drift detected: posts=%d comments=%d",
            posts_drift,
            comments_drift,
        )
    return {"posts_drift": posts_drift, "comments_drift": comments_drift}


async def _drift_for_target(
    session: AsyncSession, target_type: str, table: str
) -> int:
    rows = (
        await session.execute(
            text(
                f"SELECT t.id AS id, t.score AS stored, "  # noqa: S608  (constant table name)
                f"COALESCE(SUM(v.value), 0) AS truth "
                f"FROM {table} t "
                f"LEFT JOIN votes v ON v.target_type = :tt AND v.target_id = t.id "
                f"GROUP BY t.id, t.score"
            ),
            {"tt": target_type},
        )
    ).all()
    drift = 0
    for r in rows:
        if r.stored != r.truth:
            logger.warning(
                "drift in %s id=%d: stored=%d truth=%d",
                table,
                r.id,
                r.stored,
                r.truth,
            )
            drift += 1
    return drift


__all__ = ["recompute_hot_scores", "reconcile_score"]
