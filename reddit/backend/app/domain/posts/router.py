from datetime import datetime, timezone

from fastapi import APIRouter, HTTPException, status
from sqlalchemy import select

from app.deps import CurrentUser, SessionDep
from app.domain.posts.models import Post
from app.domain.posts.ranking import hot_score
from app.domain.posts.schemas import PostCreate, PostResponse
from app.domain.subreddits.models import Subreddit

router = APIRouter(tags=["posts"])


async def _resolve_subreddit(name: str, session: SessionDep) -> Subreddit:
    sub = (
        await session.execute(select(Subreddit).where(Subreddit.name == name))
    ).scalar_one_or_none()
    if sub is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "subreddit not found")
    return sub


@router.get("/r/{name}/new", response_model=list[PostResponse])
async def list_new(name: str, session: SessionDep, limit: int = 25) -> list[PostResponse]:
    sub = await _resolve_subreddit(name, session)
    rows = (
        await session.execute(
            select(Post)
            .where(Post.subreddit_id == sub.id, Post.deleted_at.is_(None))
            .order_by(Post.created_at.desc(), Post.id.desc())
            .limit(min(limit, 100))
        )
    ).scalars().all()
    return [PostResponse.model_validate(p) for p in rows]


@router.get("/r/{name}/hot", response_model=list[PostResponse])
async def list_hot(name: str, session: SessionDep, limit: int = 25) -> list[PostResponse]:
    sub = await _resolve_subreddit(name, session)
    rows = (
        await session.execute(
            select(Post)
            .where(Post.subreddit_id == sub.id, Post.deleted_at.is_(None))
            .order_by(Post.hot_score.desc(), Post.id.desc())
            .limit(min(limit, 100))
        )
    ).scalars().all()
    return [PostResponse.model_validate(p) for p in rows]


@router.post("/r/{name}/posts", response_model=PostResponse, status_code=status.HTTP_201_CREATED)
async def create_post(
    name: str, payload: PostCreate, current: CurrentUser, session: SessionDep
) -> PostResponse:
    sub = await _resolve_subreddit(name, session)
    now = datetime.now(timezone.utc).replace(tzinfo=None)
    initial_hot = hot_score(0, now)
    post = Post(
        subreddit_id=sub.id,
        user_id=current.id,
        title=payload.title,
        body=payload.body,
        score=0,
        hot_score=initial_hot,
        hot_recomputed_at=now,
        created_at=now,
    )
    session.add(post)
    await session.commit()
    await session.refresh(post)
    return PostResponse.model_validate(post)


@router.get("/posts/{post_id}", response_model=PostResponse)
async def get_post(post_id: int, session: SessionDep) -> PostResponse:
    post = (
        await session.execute(select(Post).where(Post.id == post_id, Post.deleted_at.is_(None)))
    ).scalar_one_or_none()
    if post is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "post not found")
    return PostResponse.model_validate(post)
