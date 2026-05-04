from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class SummarizeProxyResponse(BaseModel):
    """ai-worker /summarize の戻りに graceful degradation flag を被せた contract。"""

    summary: str | None = None
    keywords: list[str] | None = None
    degraded: bool = False
    reason: str | None = None


class PostCreate(BaseModel):
    title: str = Field(min_length=1, max_length=255)
    body: str = Field(default="", max_length=40000)


class PostResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    subreddit_id: int
    user_id: int
    title: str
    body: str
    score: int
    hot_score: float
    created_at: datetime
