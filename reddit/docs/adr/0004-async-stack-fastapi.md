# ADR 0004: 非同期 I/O スタック (FastAPI + SQLAlchemy 2.0 async + aiomysql) と JWT 認証

## ステータス

Accepted（2026-05-04）

## コンテキスト

`reddit` は本リポジトリで **2 つ目の Python バックエンドプロジェクト**。1 つ目の `instagram` は **Django/DRF (同期 ORM + Celery worker)** を採用したので、本プロジェクトは意図的に **「FastAPI / SQLAlchemy 2.0 async / aiomysql」** という **非同期 I/O 駆動**のスタックを採用し、Python 二大潮流を 1 リポジトリで対比できる構成にする。

論点は次の 2 系統:

1. **非同期 I/O スタックの選定**: FastAPI 同期 mode / FastAPI async + SQLAlchemy async / Starlette + tortoise-orm / Litestar
2. **認証方式**: rodauth-rails / Django session / DRF Token / FastAPI JWT bearer / OAuth

ローカル制約:

- 外部 SaaS なし
- ai-worker (FastAPI) は既に他プロジェクトで運用しており、**backend も FastAPI** にすると (1) ai-worker との型共有がやりやすい (2) Pydantic v2 の習熟が backend で深まる、という利点がある
- 認証は **「最小 1 経路で token 発行 → bearer で API / 投票」** で十分 (CLAUDE.md スコープ「認証手段の網羅は除外」)

## 決定

**「FastAPI (async) + SQLAlchemy 2.0 async + aiomysql + Pydantic v2 + HS256 JWT bearer」** を採用する。

- ランタイム:
  - **Python 3.12+ / FastAPI 0.115+ / SQLAlchemy 2.0 (`AsyncSession`) / aiomysql**
  - すべての route handler は `async def`、DB アクセスは `async with AsyncSession(...)` のみ
  - blocking I/O (将来のファイル読み書き等) は `asyncio.to_thread()` で逃がす規律を `coding-rules/python.md` に追記する (派生)
- レイヤリング (instagram の Django apps と同じ縦割りに合わせる):
  - `app/domain/<bounded_context>/` に `models.py / schemas.py / repository.py / service.py / router.py`
  - bounded contexts: `auth / accounts / subreddits / posts / comments / votes`
  - `app/main.py` で全 router を `include_router` する
  - `app/db.py` で `engine = create_async_engine(...)` と `get_session()` 依存性
- 認証:
  - **HS256 JWT bearer** (`Authorization: Bearer <jwt>`)
  - 登録 `POST /auth/register` / ログイン `POST /auth/login` で JWT (`sub = user_id`, `exp = +24h`) を発行
  - パスワードは **bcrypt (passlib)** でハッシュ化 (cost = 12)
  - FastAPI の `Depends(get_current_user)` で **JWT 検証 + `users` テーブル lookup** (DB lookup は派生 ADR で削減余地)
  - 公開エンドポイント (subreddit / post の閲覧、Hot 一覧) は **bearer なしでアクセス可** (Reddit と同じ閲覧 anonymous モデル)
  - 投稿 / 投票 / コメントは **bearer 必須**
- internal ingress (ai-worker → backend):
  - **`X-Internal-Token` ヘッダ** で共有 secret 検証 (`/internal/...` パスにのみ通す)
  - perplexity / discord と同じパターン (`operating-patterns.md §1`)

## 検討した選択肢

### 1. FastAPI (async) + SQLAlchemy 2.0 async + aiomysql ← 採用

- 利点: Python での非同期 I/O を **「event loop / async with / async for」レベル**で体感できる
- 利点: ai-worker (FastAPI) と **同じスタック** で、Pydantic v2 / dependency injection の習熟が共有される
- 利点: SQLAlchemy 2.0 async は instagram の Django ORM と **API 形が決定的に違う** (`session.execute(select(...))` vs `Model.objects.filter(...)`) ので、対比論点が大きい
- 欠点: SQLAlchemy 2.0 async の lazy load 制約 (`selectinload` / `joinedload` を明示する必要) が引っかかりどころ → 学習論点として有益

### 2. FastAPI 同期 mode + SQLAlchemy 同期

- 利点: シンプル
- 欠点: 非同期 I/O を学ぶ目的に反する。instagram (Django) と差が出ない
- 欠点: WebSocket / SSE 等を後段で追加する場合に async が必要になる

### 3. Starlette + tortoise-orm (Django-like async ORM)

- 利点: ORM 構文が Django に近く学習コストが低い
- 欠点: tortoise-orm のエコシステムが SQLAlchemy より薄い (migration / typing / production usage)
- 欠点: SQLAlchemy 2.0 async の learning curve を経験するという目的に反する

### 4. Litestar (旧 Starlite)

- 利点: layer / DI がきれい
- 欠点: 採用例が少なく、本リポの「実務で使われるスタック」方針 (Rails / Django / FastAPI / Go) から逸脱

### 5. 認証: rodauth-rails / Django session

- 利点: フル機能 (パスワードリセット / メール検証)
- 欠点: FastAPI 文脈では使えない / 自作になる
- 欠点: スコープ「認証手段の網羅は除外」と整合しない

### 6. 認証: DRF Token Auth

- 利点: 単純な「トークン文字列を DB に持つ」モデル
- 欠点: instagram (Django/DRF) で既に採用済み。**FastAPI なら JWT を一度経験する**ほうが対比が増える

### 7. 認証: OAuth (Authlib)

- 利点: 実運用に近い
- 欠点: 外部 IdP が必要 / ローカル完結の制約に反する / スコープ過大

## 採用理由

- **学習価値**: SQLAlchemy 2.0 async の **明示 eager load / sessionmaker / dependency injection** は本リポで未経験。Django ORM (instagram) との対比が直接価値になる
- **ai-worker との二重習熟**: backend / ai-worker が同じ FastAPI スタック → Pydantic v2 の schema 定義と内部 token フローが同じ書き味で揃う
- **JWT は本リポで 3 例目** (slack: rodauth-rails / discord: HS256 自作 / **reddit: FastAPI で HS256**)。Rails (slack/perplexity) / Go (discord) と並べて「**JWT を 3 言語で書いた**」という横軸の対比が完成する
- **anonymous read**: Reddit のドメインに合致する (ログインなしで Hot を見られる)。「リソースごとに認可ガードが要 / 不要を分ける」設計を体感

## 却下理由

- **同期 mode**: 学習目的に反する
- **tortoise-orm / Litestar**: エコシステム / 採用例が薄い
- **DRF Token / OAuth / セッション**: 既存プロジェクトで採用済み or スコープ過大

## 引き受けるトレードオフ

- **SQLAlchemy 2.0 async の lazy load 罠**: `await session.execute(select(Post))` の結果に対して `.comments` を辿ると **MissingGreenlet エラー**になる。`selectinload(Post.comments)` を明示する規律を `coding-rules/python.md` (B 章 ai-worker 規約) に追記する
- **JWT 検証の DB lookup**: 毎リクエストで `users` を引く → 派生 ADR で「JWT に必要な claim を全部入れて DB lookup を消す」余地。MVP では「ユーザの BAN/削除を即時反映できる」ことを優先して lookup を残す
- **JWT secret rotation**: HS256 で secret 1 個。MVP では rotation しない。派生 ADR で kid + secret セット管理
- **anonymous read**: rate limit がない (匿名で叩き放題)。Reddit 風 limit は派生 ADR で扱う
- **internal ingress**: `X-Internal-Token` のみで mTLS 等は使わない。本リポ全体の「設計図のみ Terraform」と整合
- **migration ツール**: SQLAlchemy 直書きの軽量 migration を Python で書く (Alembic を入れない、instagram で `manage.py migrate` を使うのと対比して **「Alembic を意図的に避けた」** という選択を残す)。派生 ADR で Alembic 化を扱う

## このADRを守るテスト / 実装ポインタ（Phase 2 以降で実装）

- `reddit/backend/app/main.py` — FastAPI app + router include + middleware
- `reddit/backend/app/db.py` — `create_async_engine` + `async_sessionmaker` + `get_session` Depends
- `reddit/backend/app/domain/auth/router.py` — `POST /auth/register` `/login`、`Depends(get_current_user)`
- `reddit/backend/app/domain/auth/security.py` — `create_access_token` / `decode_token` / `verify_password`
- `reddit/backend/app/domain/auth/middleware.py` — `X-Internal-Token` 検証 (internal router のみ)
- `reddit/backend/migrations/0001_create_users.py` — `users (id, username UNIQUE, password_hash, created_at)`
- `reddit/backend/tests/auth/test_login.py` — 登録 → login → bearer で `/me`
- `reddit/backend/tests/auth/test_anonymous_read.py` — 公開 GET (`/r/{name}/hot`) は token なしで 200
- `reddit/backend/tests/auth/test_internal_token.py` — `X-Internal-Token` 不一致で 403

## 関連 ADR

- ADR 0001: コメントツリー (投稿時に認証必須)
- ADR 0002: 投票整合性 (投票時に認証必須)
- ADR 0003: Hot ランキング (公開取得は anonymous OK)
- ADR 0005 (派生予定): JWT に role / sub を載せて DB lookup を消す
- ADR 0006 (派生予定): rate limit (anonymous + token 両方)
- ADR 0007 (派生予定): Alembic 化と migration の history 管理
