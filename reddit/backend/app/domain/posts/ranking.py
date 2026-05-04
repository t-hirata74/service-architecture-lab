"""Reddit Hot 式のローカル実装。

ai-worker (ADR 0003) と同じ式を backend 側でも持つ理由:
新規投稿の **初期 hot_score を同期計算**してから INSERT することで、
60s バッチを待たずに即座にフィードへ反映するため。
"""

from datetime import datetime, timezone
from math import log10

EPOCH_OFFSET = 1134028003  # 2005-12-08 (Reddit launch)
TIME_DIVISOR = 45000.0


def hot_score(score: int, created_at: datetime) -> float:
    if created_at.tzinfo is None:
        created_at = created_at.replace(tzinfo=timezone.utc)
    s = score
    order = log10(max(abs(s), 1))
    sign = 1 if s > 0 else (-1 if s < 0 else 0)
    seconds = created_at.timestamp() - EPOCH_OFFSET
    return round(sign * order + seconds / TIME_DIVISOR, 7)
