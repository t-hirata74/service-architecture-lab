from fastapi import APIRouter, HTTPException, status

from app.deps import CurrentUser, SessionDep
from app.domain.comments.schemas import CommentCreate, CommentResponse
from app.domain.comments.service import (
    CommentError,
    ParentMismatch,
    ParentNotFound,
    PostNotFound,
    create_comment,
    list_tree,
    soft_delete,
)

router = APIRouter(tags=["comments"])


@router.get("/posts/{post_id}/comments", response_model=list[CommentResponse])
async def list_post_comments(
    post_id: int, session: SessionDep
) -> list[CommentResponse]:
    rows = await list_tree(session, post_id=post_id)
    return [CommentResponse.model_validate(c) for c in rows]


@router.post(
    "/posts/{post_id}/comments",
    response_model=CommentResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_post_comment(
    post_id: int,
    payload: CommentCreate,
    current: CurrentUser,
    session: SessionDep,
) -> CommentResponse:
    try:
        comment = await create_comment(
            session,
            post_id=post_id,
            parent_id=payload.parent_id,
            user_id=current.id,
            body=payload.body,
        )
    except PostNotFound as exc:
        raise HTTPException(status.HTTP_404_NOT_FOUND, str(exc)) from exc
    except ParentNotFound as exc:
        raise HTTPException(status.HTTP_404_NOT_FOUND, str(exc)) from exc
    except ParentMismatch as exc:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, str(exc)) from exc
    return CommentResponse.model_validate(comment)


@router.delete("/comments/{comment_id}", response_model=CommentResponse)
async def delete_comment(
    comment_id: int, current: CurrentUser, session: SessionDep
) -> CommentResponse:
    try:
        comment = await soft_delete(session, comment_id=comment_id, user_id=current.id)
    except CommentError as exc:
        msg = str(exc)
        code = status.HTTP_404_NOT_FOUND if msg == "comment not found" else status.HTTP_403_FORBIDDEN
        raise HTTPException(code, msg) from exc
    return CommentResponse.model_validate(comment)
