"""Vote casting service (ADR 0002).

トランザクション境界:
  1. SELECT post (存在確認のみ、ロックしない)
  2. SELECT votes ... FOR UPDATE (toggle 時の既存行を lock)
  3. delta = new_value - old_value を計算
  4. INSERT or UPDATE votes (取消も `value=0` を保持、行は残す)
  5. UPDATE posts SET score = score + delta (相対加算、行レベル原子操作)
  6. COMMIT
  7. 新 score を再 SELECT (ロックを取らないので post.score を信用しない)

post 行はロックしない (ADR 0002)。`UPDATE ... SET score = score + delta` は
MySQL の行レベルで原子的なので、並行 vote が来ても sum of deltas で正しく集約される。

既知の微小レース: 同ユーザの「初回投票」が同時 2 リクエストで来ると、両方が
`existing is None` を見て INSERT しようとし、片方が UNIQUE 制約で IntegrityError
になる (second line of defense)。実用上ほぼ起き得ない。派生 ADR で
`INSERT ... ON DUPLICATE KEY UPDATE` 化すれば消える。
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

    post_exists = (
        await session.execute(
            select(Post.id).where(Post.id == post_id, Post.deleted_at.is_(None))
        )
    ).scalar_one_or_none()
    if post_exists is None:
        raise TargetNotFound("post not found")

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

    if delta != 0:
        await session.execute(
            update(Post).where(Post.id == post_id).values(score=Post.score + delta)
        )

    await session.commit()
    new_score = (await session.execute(select(Post.score).where(Post.id == post_id))).scalar_one()
    return new_score, value
