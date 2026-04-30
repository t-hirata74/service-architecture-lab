"""ai-worker: YouTube 風プロジェクトの AI 処理（モック）レイヤ。

実 LLM や実 ML モデルは呼び出さず、決定論的な処理で
レコメンド / タグ抽出 / サムネ生成 を返す。本番化するなら各関数を
OpenAI / Anthropic / 内部モデルへの呼び出しに差し替える想定。

Phase 1 ではエンドポイント形だけ用意し、Phase 4 で実装を埋める。
"""
from __future__ import annotations

from collections import Counter
import io
import re

from fastapi import FastAPI
from fastapi.responses import Response
from pydantic import BaseModel, Field

app = FastAPI(title="youtube-ai-worker", version="0.1.0")


# ---- Models ---------------------------------------------------------------

class VideoSummary(BaseModel):
    id: int
    title: str
    description: str = ""
    tags: list[str] = Field(default_factory=list)


class RecommendRequest(BaseModel):
    target: VideoSummary
    candidates: list[VideoSummary] = Field(default_factory=list)
    limit: int = Field(5, ge=1, le=50)


class RecommendItem(BaseModel):
    id: int
    title: str
    score: float


class RecommendResponse(BaseModel):
    target_id: int
    items: list[RecommendItem]


class TagsRequest(BaseModel):
    title: str = Field(..., min_length=1, max_length=200)
    description: str = Field("", max_length=5000)


class TagsResponse(BaseModel):
    tags: list[str]


class ThumbnailRequest(BaseModel):
    video_id: int
    title: str = Field(..., min_length=1, max_length=200)


# ---- Endpoints ------------------------------------------------------------

@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "service": "youtube-ai-worker"}


@app.post("/recommend", response_model=RecommendResponse)
def recommend(req: RecommendRequest) -> RecommendResponse:
    """タグ重複度ベースの素朴なスコアリングで類似動画を返す。"""
    target_tags = set(req.target.tags)
    scored: list[tuple[float, VideoSummary]] = []
    for c in req.candidates:
        if c.id == req.target.id:
            continue
        overlap = len(target_tags & set(c.tags))
        union = len(target_tags | set(c.tags)) or 1
        score = overlap / union  # Jaccard
        scored.append((score, c))
    scored.sort(key=lambda x: x[0], reverse=True)
    items = [
        RecommendItem(id=c.id, title=c.title, score=round(s, 4))
        for s, c in scored[: req.limit]
    ]
    return RecommendResponse(target_id=req.target.id, items=items)


_WORD_RE = re.compile(r"[A-Za-z0-9_\u3040-\u30ff\u4e00-\u9fff]+")
_STOPWORDS = {"the", "a", "an", "of", "is", "are", "to", "in", "on", "for", "and", "or"}


@app.post("/tags/extract", response_model=TagsResponse)
def extract_tags(req: TagsRequest) -> TagsResponse:
    """タイトル・説明文から頻度ベースで簡易タグ抽出 (モック)。"""
    text = f"{req.title} {req.description}".lower()
    words = [w for w in _WORD_RE.findall(text) if len(w) >= 2 and w not in _STOPWORDS]
    counts = Counter(words)
    tags = [w for w, _ in counts.most_common(8)]
    return TagsResponse(tags=tags)


@app.post("/thumbnail")
def generate_thumbnail(req: ThumbnailRequest) -> Response:
    """サムネ画像 (PNG) を Pillow で生成して返す。実コーデック処理はしない。"""
    from PIL import Image, ImageDraw

    img = Image.new("RGB", (640, 360), color=(30, 30, 30))
    draw = ImageDraw.Draw(img)
    text = req.title[:40]
    # フォントは未指定 (デフォルト)。学習用なので体裁よりも生成パイプラインを示す。
    draw.text((20, 160), f"#{req.video_id} {text}", fill=(240, 240, 240))
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return Response(content=buf.getvalue(), media_type="image/png")
