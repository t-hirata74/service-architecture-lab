from fastapi import APIRouter, HTTPException, status

from app.deps import CurrentUser, SessionDep
from app.domain.votes.schemas import VoteRequest, VoteResponse
from app.domain.votes.service import TargetNotFound, VoteError, cast_vote_on_post

router = APIRouter(tags=["votes"])


@router.post("/posts/{post_id}/vote", response_model=VoteResponse)
async def vote_on_post(
    post_id: int, payload: VoteRequest, current: CurrentUser, session: SessionDep
) -> VoteResponse:
    try:
        new_score, user_value = await cast_vote_on_post(
            session, user_id=current.id, post_id=post_id, value=payload.value
        )
    except TargetNotFound as exc:
        raise HTTPException(status.HTTP_404_NOT_FOUND, str(exc)) from exc
    except VoteError as exc:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, str(exc)) from exc
    return VoteResponse(target_id=post_id, score=new_score, user_value=user_value)
