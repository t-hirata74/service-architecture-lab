"""ai-worker: メッセージ要約のモック実装。

実際の LLM 呼び出しは行わず、入力メッセージから決定論的に要約を生成する。
本番化するなら summarize_messages の中身を OpenAI/Anthropic 等のクライアント呼び出しに差し替える想定。
"""
from collections import Counter

from fastapi import FastAPI
from pydantic import BaseModel, Field

app = FastAPI(title="slack-ai-worker", version="0.1.0")


class Message(BaseModel):
    id: int
    user: str
    body: str


class SummarizeRequest(BaseModel):
    channel_name: str = Field(..., min_length=1, max_length=200)
    messages: list[Message] = Field(default_factory=list)


class SummarizeResponse(BaseModel):
    channel_name: str
    message_count: int
    participants: list[str]
    summary: str


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/summarize", response_model=SummarizeResponse)
def summarize(req: SummarizeRequest) -> SummarizeResponse:
    if not req.messages:
        return SummarizeResponse(
            channel_name=req.channel_name,
            message_count=0,
            participants=[],
            summary="まだ会話がありません。",
        )

    participants = sorted({m.user for m in req.messages})
    user_counts = Counter(m.user for m in req.messages)
    top_speakers = ", ".join(
        f"{user} ({count}件)" for user, count in user_counts.most_common(3)
    )

    # 最初と最後のメッセージから話題を抽出 (モック: 単純に冒頭を抜粋)
    first_excerpt = _excerpt(req.messages[0].body)
    last_excerpt = _excerpt(req.messages[-1].body)

    summary = (
        f"#{req.channel_name} には {len(req.messages)} 件のメッセージ。"
        f" 主な発言者: {top_speakers}。"
        f" 話題は「{first_excerpt}」から始まり「{last_excerpt}」で終わっています。"
    )

    return SummarizeResponse(
        channel_name=req.channel_name,
        message_count=len(req.messages),
        participants=participants,
        summary=summary,
    )


def _excerpt(text: str, limit: int = 30) -> str:
    cleaned = " ".join(text.split())
    if len(cleaned) <= limit:
        return cleaned
    return cleaned[:limit] + "…"
