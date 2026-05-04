"""ai-worker 設定。Rails backend からの内部 ingress は X-Internal-Token で認証する。"""

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    internal_token: str = "dev-internal-token"
    port: int = 8070


@lru_cache
def get_settings() -> Settings:
    return Settings()
