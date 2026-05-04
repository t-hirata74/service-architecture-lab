from pydantic import BaseModel, Field


class VoteRequest(BaseModel):
    value: int = Field(ge=-1, le=1)


class VoteResponse(BaseModel):
    target_id: int
    score: int
    user_value: int
