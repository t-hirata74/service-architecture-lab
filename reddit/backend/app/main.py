from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

import app.models  # noqa: F401  (register all mappers)
from app.db import Base, get_engine
from app.domain.accounts.router import router as auth_router
from app.domain.posts.router import router as posts_router
from app.domain.subreddits.router import router as subreddits_router
from app.domain.votes.router import router as votes_router


@asynccontextmanager
async def lifespan(app: FastAPI):
    yield


def create_app() -> FastAPI:
    app = FastAPI(title="Reddit clone (FastAPI)", lifespan=lifespan)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["http://localhost:3065"],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    app.include_router(auth_router)
    app.include_router(subreddits_router)
    app.include_router(posts_router)
    app.include_router(votes_router)

    @app.get("/health")
    async def health() -> dict:
        return {"ok": True}

    return app


async def init_db() -> None:
    """Lightweight migration: create all tables from Base.metadata.

    ADR 0004 で「Alembic を入れない、SQLAlchemy 直書きの軽量 migration」
    と決めた通り、create_all() を migrate コマンド代わりにする。
    """
    engine = get_engine()
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)


app = create_app()
