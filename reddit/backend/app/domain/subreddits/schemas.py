from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class SubredditCreate(BaseModel):
    name: str = Field(min_length=2, max_length=64, pattern=r"^[A-Za-z0-9_]+$")
    description: str = Field(default="", max_length=1024)


class SubredditResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    description: str
    created_by: int
    created_at: datetime


class SubscribeResponse(BaseModel):
    subscribed: bool
