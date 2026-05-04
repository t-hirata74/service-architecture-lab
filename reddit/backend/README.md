# reddit/backend (FastAPI / async)

ADR 0004 に従った FastAPI + SQLAlchemy 2.0 async + aiomysql + HS256 JWT 実装。

## レイアウト

```
backend/
  app/
    main.py            # FastAPI app + lifespan + init_db (= Base.metadata.create_all)
    cli.py             # `python -m app.cli migrate`
    config.py          # pydantic-settings
    db.py              # async engine / sessionmaker / get_session
    deps.py            # CurrentUser / CurrentUserOptional / require_internal_token
    security.py        # bcrypt + JWT (HS256)
    models.py          # 全 mapper を import (Base.metadata に集約)
    domain/
      accounts/        # users / register / login / me
      subreddits/      # subreddits + memberships + subscribe toggle
      posts/           # posts CRUD + new/hot 一覧 + Reddit Hot 式 (ranking.py)
      votes/           # ADR 0002 の vote service (with_for_update + 相対加算)
      comments/        # Phase 3 で実装
  tests/               # pytest-asyncio + httpx ASGITransport (sqlite in-memory)
```

## 起動

```bash
docker compose up -d mysql           # 3313 (リポジトリ root から)
cd reddit/backend
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python -m app.cli migrate            # Base.metadata.create_all
uvicorn app.main:app --port 3070 --reload
```

## テスト

```bash
pytest
```

テストは sqlite in-memory + httpx ASGITransport で実行 (MySQL は不要)。
`with_for_update()` は sqlite で no-op になるが、ロジック自体は MySQL でも同じ。

## Phase 2 の到達点

- 17 tests pass: `health / auth (4) / subreddits (4) / posts (3) / votes (5)`
- 投票は **`SELECT ... FOR UPDATE` → INSERT/UPDATE → 相対加算 UPDATE → COMMIT** の固定順
- 新規投稿は **同期的に Reddit Hot 式の初期値を計算**してから INSERT (ADR 0003)

## Phase 3 以降

- comments ツリー (ADR 0001 path 採番)
- ai-worker (FastAPI + APScheduler) で Hot 再計算 + reconcile job
- frontend (Next.js)
