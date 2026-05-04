from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class CommentCreate(BaseModel):
    body: str = Field(min_length=1, max_length=10000)
    parent_id: int | None = None


class CommentResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    post_id: int
    parent_id: int | None
    path: str
    depth: int
    user_id: int
    body: str
    score: int
    deleted_at: datetime | None
    created_at: datetime
