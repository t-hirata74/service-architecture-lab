"""ai-worker 設定。Rails backend からの内部 ingress は Authorization: Bearer で認証する。"""

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # Rails 側 Internal::Client が送る Bearer token (ADR 0003)。
    internal_token: str = "dev-internal-token"
    port: int = 8080


@lru_cache
def get_settings() -> Settings:
    return Settings()
