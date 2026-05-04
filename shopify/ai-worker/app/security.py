"""内部 ingress の認証。本リポ共通パターン (perplexity / instagram / reddit) と同形式。"""

from fastapi import Header, HTTPException, status

from app.config import get_settings


async def verify_internal_token(x_internal_token: str | None = Header(default=None)) -> None:
    expected = get_settings().internal_token
    if not x_internal_token or x_internal_token != expected:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="invalid internal token")
