"""ADR 0003 — Reddit Hot 式の値検証。

backend/app/domain/posts/ranking.py に同じ式を duplicate しているので、
両者が同じ value を返すことも保証する。
"""

import importlib.util
from datetime import datetime, timezone
from pathlib import Path

from app.ranking import EPOCH_OFFSET, TIME_DIVISOR, hot_score


def test_zero_score_only_time_term():
    dt = datetime(2026, 5, 4, 12, 0, 0, tzinfo=timezone.utc)
    expected = round((dt.timestamp() - EPOCH_OFFSET) / TIME_DIVISOR, 7)
    assert hot_score(0, dt) == expected


def test_positive_vs_negative_sign():
    dt = datetime(2026, 5, 4, 12, 0, 0, tzinfo=timezone.utc)
    pos = hot_score(100, dt)
    neg = hot_score(-100, dt)
    # log10(100) = 2.0; positive should be ~4 higher than negative
    assert pos - neg == 4.0


def test_log_scaling_compresses_score():
    dt = datetime(2026, 5, 4, 12, 0, 0, tzinfo=timezone.utc)
    # score=10 → log10(10)=1, score=100 → log10(100)=2 → diff = 1.0
    diff = hot_score(100, dt) - hot_score(10, dt)
    assert diff == 1.0


def test_newer_post_ranks_higher_at_same_score():
    older = datetime(2026, 1, 1, tzinfo=timezone.utc)
    newer = datetime(2026, 5, 1, tzinfo=timezone.utc)
    assert hot_score(10, newer) > hot_score(10, older)


def test_ai_worker_and_backend_formula_match():
    """両プロジェクトの hot_score 実装が同じ値を返す."""
    backend_ranking_path = (
        Path(__file__).resolve().parents[2]
        / "backend"
        / "app"
        / "domain"
        / "posts"
        / "ranking.py"
    )
    spec = importlib.util.spec_from_file_location("backend_ranking", backend_ranking_path)
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)

    dt = datetime(2026, 5, 4, 12, 0, 0, tzinfo=timezone.utc)
    for s in (-50, -1, 0, 1, 100, 9999):
        assert hot_score(s, dt) == mod.hot_score(s, dt), s
