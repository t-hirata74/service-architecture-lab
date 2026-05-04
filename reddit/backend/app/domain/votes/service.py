"""Vote casting service (ADR 0002).

post / comment 共通フロー:
  1. SELECT target (存在確認のみ、ロックしない)
  2. SELECT votes ... FOR UPDATE (toggle 時の既存行を lock)
  3. delta = new_value - old_value
  4. INSERT or UPDATE votes (取消も `value=0` を保持、行は残す)
  5. UPDATE target SET score = score + delta (相対加算、行レベル原子操作)
  6. COMMIT
  7. 新 score を再 SELECT

target 行はロックしない (ADR 0002)。`UPDATE ... SET score = score + delta` は
MySQL 行レベルで原子的なので、並行 vote が来ても sum of deltas で正しく集約される。

既知の微小レース: 同ユーザの「初回投票」が同時 2 リクエストで来ると、両方が
`existing is None` を見て INSERT しようとし、片方が UNIQUE 制約で IntegrityError
になる (second line of defense)。実用上ほぼ起き得ない。派生 ADR で
`INSERT ... ON DUPLICATE KEY UPDATE` 化すれば消える。
"""

from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.domain.comments.models import Comment
from app.domain.posts.models import Post
from app.domain.votes.models import Vote, VoteTargetType


class VoteError(Exception):
    pass


class TargetNotFound(VoteError):
    pass


_TARGET_MODELS = {
    VoteTargetType.POST: Post,
    VoteTargetType.COMMENT: Comment,
}


async def _cast(
    session: AsyncSession,
    *,
    target_type: VoteTargetType,
    target_id: int,
    user_id: int,
    value: int,
) -> tuple[int, int]:
    if value not in (-1, 0, 1):
        raise VoteError("value must be -1, 0, or 1")

    model = _TARGET_MODELS[target_type]

    target_exists = (
        await session.execute(
            select(model.id).where(model.id == target_id, model.deleted_at.is_(None))
        )
    ).scalar_one_or_none()
    if target_exists is None:
        raise TargetNotFound(f"{target_type.value} not found")

    existing = (
        await session.execute(
            select(Vote)
            .where(
                Vote.user_id == user_id,
                Vote.target_type == target_type,
                Vote.target_id == target_id,
            )
            .with_for_update()
        )
    ).scalar_one_or_none()

    old_value = existing.value if existing else 0
    delta = value - old_value

    if existing is None:
        session.add(
            Vote(
                user_id=user_id,
                target_type=target_type,
                target_id=target_id,
                value=value,
            )
        )
    elif delta != 0:
        existing.value = value

    if delta != 0:
        await session.execute(
            update(model).where(model.id == target_id).values(score=model.score + delta)
        )

    await session.commit()
    new_score = (
        await session.execute(select(model.score).where(model.id == target_id))
    ).scalar_one()
    return new_score, value


async def cast_vote_on_post(
    session: AsyncSession, *, user_id: int, post_id: int, value: int
) -> tuple[int, int]:
    return await _cast(
        session,
        target_type=VoteTargetType.POST,
        target_id=post_id,
        user_id=user_id,
        value=value,
    )


async def cast_vote_on_comment(
    session: AsyncSession, *, user_id: int, comment_id: int, value: int
) -> tuple[int, int]:
    return await _cast(
        session,
        target_type=VoteTargetType.COMMENT,
        target_id=comment_id,
        user_id=user_id,
        value=value,
    )
