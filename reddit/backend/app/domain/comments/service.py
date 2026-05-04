"""Comment tree service (ADR 0001).

`comments` は Adjacency List (`parent_id`) + Materialized Path (`path`) のハイブリッド。
path は 10 桁 0 埋め id を `/` 区切り (例: ``0000000001/0000000004``)。

create_comment は **2 段 INSERT** で path を採番:
  1. INSERT (path='', depth=0) → flush で id を確定
  2. UPDATE path / depth (親 path から組み立てる)

両方が同一トランザクションに乗るので、path 空のレコードが他者から見えない。
"""

from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.domain.comments.models import Comment
from app.domain.posts.models import Post

PATH_PAD = 10  # 10 桁 0 埋め: 10 億件まで lexicographic 順 = preorder を維持できる


def _path_segment(comment_id: int) -> str:
    return f"{comment_id:0{PATH_PAD}d}"


class CommentError(Exception):
    pass


class CommentNotFound(CommentError):
    pass


class PostNotFound(CommentError):
    pass


class ParentNotFound(CommentError):
    pass


class ParentMismatch(CommentError):
    pass


class NotAuthor(CommentError):
    pass


async def create_comment(
    session: AsyncSession,
    *,
    post_id: int,
    parent_id: int | None,
    user_id: int,
    body: str,
) -> Comment:
    post_exists = (
        await session.execute(
            select(Post.id).where(Post.id == post_id, Post.deleted_at.is_(None))
        )
    ).scalar_one_or_none()
    if post_exists is None:
        raise PostNotFound("post not found")

    parent: Comment | None = None
    if parent_id is not None:
        parent = (
            await session.execute(select(Comment).where(Comment.id == parent_id))
        ).scalar_one_or_none()
        if parent is None:
            raise ParentNotFound("parent comment not found")
        if parent.post_id != post_id:
            raise ParentMismatch("parent comment belongs to a different post")

    comment = Comment(
        post_id=post_id,
        parent_id=parent_id,
        path="",
        depth=0,
        user_id=user_id,
        body=body,
    )
    session.add(comment)
    await session.flush()  # assigns comment.id

    segment = _path_segment(comment.id)
    if parent is None:
        comment.path = segment
        comment.depth = 1
    else:
        comment.path = f"{parent.path}/{segment}"
        comment.depth = parent.depth + 1

    await session.commit()
    await session.refresh(comment)
    return comment


async def list_tree(session: AsyncSession, *, post_id: int) -> list[Comment]:
    # ADR 0001: soft-deleted comments も返す。子コメントを残すため、
    # frontend で deleted_at を見て「[deleted]」プレースホルダを描画する。
    stmt = (
        select(Comment).where(Comment.post_id == post_id).order_by(Comment.path)
    )
    return list((await session.execute(stmt)).scalars().all())


async def soft_delete(
    session: AsyncSession, *, comment_id: int, user_id: int
) -> Comment:
    comment = (
        await session.execute(select(Comment).where(Comment.id == comment_id))
    ).scalar_one_or_none()
    if comment is None:
        raise CommentNotFound("comment not found")
    if comment.user_id != user_id:
        raise NotAuthor("not the author")
    if comment.deleted_at is None:
        comment.deleted_at = datetime.now(timezone.utc).replace(tzinfo=None)
        await session.commit()
        await session.refresh(comment)
    return comment
