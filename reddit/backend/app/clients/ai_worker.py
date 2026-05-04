"""ai-worker への outbound HTTP client.

graceful degradation (operating-patterns §2): ai-worker 不通 / 5xx / タイムアウトの場合は
`{degraded: True, ...}` を返す。Frontend は degraded を見て fallback UI を出す前提。
"""

from __future__ import annotations

import logging
from typing import Any

import httpx

from app.config import get_settings

logger = logging.getLogger("ai-worker-client")
TIMEOUT_SECONDS = 3.0


async def _post(path: str, payload: dict[str, Any]) -> dict[str, Any]:
    settings = get_settings()
    url = f"{settings.ai_worker_url}{path}"
    headers = {"X-Internal-Token": settings.internal_token}
    try:
        async with httpx.AsyncClient(timeout=TIMEOUT_SECONDS) as client:
            res = await client.post(url, json=payload, headers=headers)
    except httpx.RequestError as exc:
        # ConnectError / TimeoutException など接続レベル
        logger.warning("ai-worker %s unreachable: %s", path, exc)
        return {"degraded": True, "reason": "unreachable"}

    if res.status_code >= 500:
        logger.warning("ai-worker %s returned %d", path, res.status_code)
        return {"degraded": True, "reason": f"upstream_{res.status_code}"}
    if res.status_code >= 400:
        # 4xx は contract 不一致 (token / schema)。本来 bug だが、frontend には
        # graceful degradation で見せて運用継続する。
        logger.warning("ai-worker %s contract error %d", path, res.status_code)
        return {"degraded": True, "reason": f"upstream_{res.status_code}"}
    body = res.json()
    body.setdefault("degraded", False)
    return body


async def summarize(*, title: str, body: str) -> dict[str, Any]:
    return await _post("/summarize", {"title": title, "body": body})


async def related(*, subreddit: str) -> dict[str, Any]:
    return await _post("/related", {"subreddit": subreddit})


async def spam_check(*, body: str) -> dict[str, Any]:
    return await _post("/spam-check", {"body": body})
