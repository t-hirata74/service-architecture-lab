from fastapi import APIRouter, HTTPException, status
from sqlalchemy import delete, select
from sqlalchemy.exc import IntegrityError

from app.deps import CurrentUser, SessionDep
from app.domain.subreddits.models import Subreddit, SubredditMembership
from app.domain.subreddits.schemas import (
    SubredditCreate,
    SubredditResponse,
    SubscribeResponse,
)

router = APIRouter(prefix="/r", tags=["subreddits"])


@router.get("", response_model=list[SubredditResponse])
async def list_subreddits(session: SessionDep) -> list[SubredditResponse]:
    result = (
        await session.execute(select(Subreddit).order_by(Subreddit.created_at.desc()).limit(100))
    ).scalars().all()
    return [SubredditResponse.model_validate(s) for s in result]


@router.post("", response_model=SubredditResponse, status_code=status.HTTP_201_CREATED)
async def create_subreddit(
    payload: SubredditCreate, current: CurrentUser, session: SessionDep
) -> SubredditResponse:
    sub = Subreddit(name=payload.name, description=payload.description, created_by=current.id)
    session.add(sub)
    try:
        await session.flush()
    except IntegrityError as exc:
        await session.rollback()
        raise HTTPException(status.HTTP_409_CONFLICT, "subreddit name already taken") from exc
    session.add(SubredditMembership(subreddit_id=sub.id, user_id=current.id))
    await session.commit()
    await session.refresh(sub)
    return SubredditResponse.model_validate(sub)


@router.get("/{name}", response_model=SubredditResponse)
async def get_subreddit(name: str, session: SessionDep) -> SubredditResponse:
    sub = (
        await session.execute(select(Subreddit).where(Subreddit.name == name))
    ).scalar_one_or_none()
    if sub is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "subreddit not found")
    return SubredditResponse.model_validate(sub)


@router.post("/{name}/subscribe", response_model=SubscribeResponse)
async def toggle_subscribe(
    name: str, current: CurrentUser, session: SessionDep
) -> SubscribeResponse:
    sub = (
        await session.execute(select(Subreddit).where(Subreddit.name == name))
    ).scalar_one_or_none()
    if sub is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "subreddit not found")

    existing = (
        await session.execute(
            select(SubredditMembership).where(
                SubredditMembership.subreddit_id == sub.id,
                SubredditMembership.user_id == current.id,
            )
        )
    ).scalar_one_or_none()

    if existing is None:
        session.add(SubredditMembership(subreddit_id=sub.id, user_id=current.id))
        await session.commit()
        return SubscribeResponse(subscribed=True)

    await session.execute(
        delete(SubredditMembership).where(SubredditMembership.id == existing.id)
    )
    await session.commit()
    return SubscribeResponse(subscribed=False)
