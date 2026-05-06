"""内部 ingress の Bearer 認証。Rails の `Internal::Client` (httpx) が送る `Authorization: Bearer <token>` を検証する。"""

from fastapi import Header, HTTPException, status

from app.config import get_settings


async def verify_internal_token(authorization: str | None = Header(default=None)) -> None:
    expected = get_settings().internal_token
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="missing bearer token")

    token = authorization.removeprefix("Bearer ").strip()
    if token != expected:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="invalid internal token")
