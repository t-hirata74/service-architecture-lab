from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str = "mysql+aiomysql://reddit:reddit@127.0.0.1:3313/reddit_development"
    internal_token: str = "dev-internal-token"

    # ADR 0003: Hot 再計算の interval。本番運用なら 60s、テストでは無効化したい。
    hot_recompute_interval_seconds: int = 60
    # 直近 N 日分のみ recompute 対象にする。
    hot_recompute_window_days: int = 7
    enable_scheduler: bool = True


@lru_cache
def get_settings() -> Settings:
    return Settings()
