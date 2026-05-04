"""Vote casting service (ADR 0002).

トランザクション境界:
  1. SELECT votes ... FOR UPDATE で既存値を取得
  2. delta = new_value - old_value を計算
  3. INSERT or UPDATE votes (取消も `value=0` を保持、行は残す)
  4. UPDATE posts SET score = score + delta (相対加算)
  5. COMMIT

相対加算なので、同一 post への並行 vote が来ても row lock 順に直列化されるだけで
最終的な score は ((sum of deltas)) と一致し race-free。
"""

from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.domain.posts.models import Post
from app.domain.votes.models import Vote, VoteTargetType


class VoteError(Exception):
    pass


class TargetNotFound(VoteError):
    pass


async def cast_vote_on_post(
    session: AsyncSession, *, user_id: int, post_id: int, value: int
) -> tuple[int, int]:
    """Returns (new_post_score, user_value)."""
    if value not in (-1, 0, 1):
        raise VoteError("value must be -1, 0, or 1")

    # 1. lock the post row (確実な行存在 + score 整合の起点)
    post = (
        await session.execute(
            select(Post).where(Post.id == post_id, Post.deleted_at.is_(None)).with_for_update()
        )
    ).scalar_one_or_none()
    if post is None:
        raise TargetNotFound("post not found")

    # 2. 既存 vote 行（あれば lock）
    existing = (
        await session.execute(
            select(Vote)
            .where(
                Vote.user_id == user_id,
                Vote.target_type == VoteTargetType.POST,
                Vote.target_id == post_id,
            )
            .with_for_update()
        )
    ).scalar_one_or_none()

    old_value = existing.value if existing else 0
    delta = value - old_value

    # 3. votes upsert (取消でも行は保持、value=0 にするだけ)
    if existing is None:
        session.add(
            Vote(
                user_id=user_id,
                target_type=VoteTargetType.POST,
                target_id=post_id,
                value=value,
            )
        )
    elif delta != 0:
        existing.value = value

    # 4. 相対加算
    if delta != 0:
        await session.execute(
            update(Post).where(Post.id == post_id).values(score=Post.score + delta)
        )

    await session.commit()
    new_score = (await session.execute(select(Post.score).where(Post.id == post_id))).scalar_one()
    return new_score, value
