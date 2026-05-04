from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str = "mysql+aiomysql://reddit:reddit@127.0.0.1:3313/reddit_development"
    jwt_secret: str = "dev-secret-do-not-use-in-prod"
    jwt_algorithm: str = "HS256"
    access_token_ttl_seconds: int = 60 * 60 * 24
    internal_token: str = "dev-internal-token"
    ai_worker_url: str = "http://127.0.0.1:8060"


@lru_cache
def get_settings() -> Settings:
    return Settings()
