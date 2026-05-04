"""recompute_hot_scores と reconcile_score のテスト."""

from datetime import datetime, timedelta, timezone

from sqlalchemy import text

from app.jobs import recompute_hot_scores, reconcile_score


async def _seed(session, *, score, hours_ago):
    now = datetime.now(timezone.utc).replace(tzinfo=None)
    created = now - timedelta(hours=hours_ago)
    await session.execute(
        text("INSERT INTO users (username, password_hash) VALUES ('u', 'x')")
    )
    await session.execute(
        text(
            "INSERT INTO subreddits (name, created_by) VALUES ('python', 1)"
        )
    )
    await session.execute(
        text(
            "INSERT INTO posts (subreddit_id, user_id, title, score, hot_score, created_at) "
            "VALUES (1, 1, 't', :score, 0.0, :created)"
        ),
        {"score": score, "created": created},
    )
    await session.commit()


async def test_recompute_updates_recent_post(session):
    await _seed(session, score=10, hours_ago=1)
    n = await recompute_hot_scores(session=session)
    assert n == 1
    row = (await session.execute(text("SELECT hot_score FROM posts WHERE id=1"))).one()
    assert row.hot_score != 0.0  # was overwritten


async def test_recompute_skips_old_post(session):
    # 30 日前 → 7 日窓の外
    await _seed(session, score=10, hours_ago=24 * 30)
    n = await recompute_hot_scores(session=session)
    assert n == 0
    row = (await session.execute(text("SELECT hot_score FROM posts WHERE id=1"))).one()
    assert row.hot_score == 0.0


async def test_recompute_skips_soft_deleted(session):
    await _seed(session, score=10, hours_ago=1)
    await session.execute(
        text("UPDATE posts SET deleted_at = :now WHERE id=1"),
        {"now": datetime.now(timezone.utc).replace(tzinfo=None)},
    )
    await session.commit()
    n = await recompute_hot_scores(session=session)
    assert n == 0


async def test_reconcile_detects_drift(session):
    await _seed(session, score=10, hours_ago=1)
    # 真値は votes SUM。1 票しか votes になく score=10 と乖離
    await session.execute(
        text(
            "INSERT INTO votes (user_id, target_type, target_id, value) "
            "VALUES (1, 'post', 1, 1)"
        )
    )
    await session.commit()
    result = await reconcile_score(session=session)
    assert result["posts_drift"] == 1


async def test_reconcile_no_drift(session):
    await _seed(session, score=0, hours_ago=1)  # score=0 / 0 votes → match
    result = await reconcile_score(session=session)
    assert result == {"posts_drift": 0, "comments_drift": 0}
