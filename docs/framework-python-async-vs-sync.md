# Python Web フレームワーク選定 — 同期 (Django/Celery) vs 非同期 (FastAPI/APScheduler)

本リポでは Rails (主軸) に加えて **Python の 2 大潮流**を 1 リポジトリで対比して習得する位置づけ:

- **同期 ORM + Celery (broker = Redis)** — `instagram/backend/` (Django/DRF)
- **非同期 I/O + APScheduler (DB 直)** — `reddit/backend/` (FastAPI + SQLAlchemy 2.0 async)

このドキュメントは「同じ Python でも、フレームワーク選択でアプリ全体の形がここまで変わる」という比較資料。

> 個別の規約は [`coding-rules/python.md`](coding-rules/python.md) (B) Django / (C) FastAPI async に分けて書いてある。本ドキュメントは **「どっちを選ぶか」「何が違うか」** に焦点を絞る。

---

## サマリ — 5 軸での違い

| 軸 | Django (instagram) | FastAPI async (reddit) |
| --- | --- | --- |
| **route handler** | `def view(request)` 同期 | `async def view(...)` |
| **ORM** | Django ORM 同期 (`Model.objects.filter`) | SQLAlchemy 2.0 async (`select(Model)` + `await session.execute`) |
| **non-blocking** | gunicorn worker 多重化で並列化 (1 リクエスト = 1 worker 占有) | event loop 単一プロセスで多重化 (1 worker = 数百 連接続) |
| **非同期処理** | **Celery worker** (別プロセス、broker = Redis) | **APScheduler** (同プロセス、scheduler = AsyncIOScheduler) |
| **副作用 trigger** | Django signal + `transaction.on_commit` | service 関数内で直接記述 (signal 機構なし) |
| **管理画面** | Django Admin (1 行登録で CRUD UI) | なし (作るなら自作) |
| **migration** | `manage.py makemigrations` (history 管理) | reddit MVP では `Base.metadata.create_all` のみ。本格運用は Alembic |
| **N+1 制御** | `select_related` / `prefetch_related` 明示 + `assertNumQueries` で固定 | `selectinload` / `joinedload` 明示 (lazy load は MissingGreenlet で落ちる) |
| **counter 整合** | `F("count") ± 1` + `recount_<model>_stats` management command | 相対加算 `UPDATE ... SET score = score + delta` + ai-worker reconcile job |
| **テスト** | pytest-django + MySQL service (CI) | pytest-asyncio + httpx ASGITransport + sqlite in-memory (MySQL 不要) |

---

## 1. route handler のスループットモデル

### Django: gunicorn worker 多重化

```python
# views.py
@api_view(["GET"])
def list_posts(request):
    posts = Post.objects.select_related("user").all()
    return Response(PostSerializer(posts, many=True).data)
```

- 1 リクエスト = 1 worker thread が DB query / serializer / network I/O すべてを **同期で**処理
- 並列度は gunicorn の `--workers` × `--threads` の積で決まる
- **DB 接続を per-request で握る**ので、worker × threads = 同時接続数の上限。pgbouncer / ProxySQL を前段に置く場合あり

### FastAPI async: event loop 1 プロセスで数百

```python
# router.py
@router.get("/r/{name}/hot")
async def list_hot(name: str, session: SessionDep):
    rows = (await session.execute(
        select(Post).where(...).order_by(Post.hot_score.desc()).limit(25)
    )).scalars().all()
    return [PostResponse.model_validate(p) for p in rows]
```

- 1 worker (event loop) が **数百のリクエスト**を await で多重化
- DB 接続は **connection pool** (SQLAlchemy が管理) を coroutine 間で使い回す
- I/O wait 中は他の coroutine が走る → スループットが上がる
- **ただし** `async def` 内で同期 I/O (requests / time.sleep / 同期 DB) を呼ぶと event loop が止まる罠

### 選定軸

| やりたいこと | 選択 |
| --- | --- |
| 数百同時の long-lived 接続を捌きたい (SSE / WebSocket 隣接) | FastAPI async |
| CPU bound (画像処理 / ML 推論) が中心 | Django (worker thread が直感的) |
| DB connection を厳密に管理したい (pgbouncer 前提) | Django (per-request 接続が分かりやすい) |
| 既存 ML スタック (numpy/pandas) を直接 import | Django でも FastAPI でも可 (どちらも同期 import OK) |

---

## 2. 非同期処理 — Celery worker vs APScheduler

両者は **思想が決定的に違う**。

### Django: Celery worker (broker = Redis、別プロセス)

```python
# instagram/backend/timeline/tasks.py
@shared_task(queue="fanout")
def fanout_post_to_followers(post_id: int):
    ...

# posts/signals.py
@receiver(post_save, sender=Post)
def on_post_created(sender, instance, created, **kwargs):
    if created:
        transaction.on_commit(lambda: fanout_post_to_followers.delay(instance.pk))
```

- broker (Redis) を介して **別プロセスで実行**
- 失敗時の retry / dead letter queue / 並列スケール (worker N 台) が無料で付く
- **trade-off**: broker (Redis) の運用 + worker のデプロイが増える。test では `CELERY_TASK_ALWAYS_EAGER = True` で同期化する技が必要 ([testing-strategy.md](testing-strategy.md#celery-task_always_eager-を-django-settings-側で書き換える罠))

### FastAPI: APScheduler (同プロセス、scheduler = AsyncIOScheduler)

```python
# reddit/ai-worker/app/main.py
@asynccontextmanager
async def lifespan(app: FastAPI):
    sched = AsyncIOScheduler()
    sched.add_job(recompute_hot_scores, "interval", seconds=60, max_instances=1, coalesce=True)
    sched.add_job(reconcile_score, "cron", hour=3, max_instances=1, coalesce=True)
    sched.start()
    yield
    sched.shutdown(wait=False)
```

- broker なし、**プロセス内 scheduler** が job を triggers
- 失敗時の retry は自前で書く (or `apscheduler.misfire_grace_time` で粗く)
- **trade-off**: 複数台に分散すると scheduler が重複起動する → ECS desired_count=1 を Terraform で固定 ([operating-patterns §16](operating-patterns.md#16-apscheduler-driven-batch--single-instance-constraint-reddit) 規律 2)
- test は **scheduler を起動せず**、ジョブ関数を直接 await ([testing-strategy.md FastAPI 節](testing-strategy.md#fastapi-async-backend-reddit) 規律 3)

### 選定軸

| やりたいこと | 選択 |
| --- | --- |
| at-least-once 配信、retry / DLQ が欲しい | Celery |
| scale-out (worker N 台 同並列) が欲しい | Celery |
| **周期 batch (毎分 / nightly) が中心**で broker を増やしたくない | APScheduler |
| 単一インスタンス前提 / 軽量に済ませたい | APScheduler |
| 「投稿のたびに走らせる per-event task」が中心 | Celery (APScheduler は周期 trigger 中心) |

reddit が APScheduler を選んだのは **Hot 再計算 (周期 batch) + reconcile (nightly)** が中心で、per-event task が無いから。instagram は **fan-out (per-event)** が中心なので Celery 一択だった。

---

## 3. 副作用 trigger の流派

### Django: signal + `transaction.on_commit`

```python
@receiver(post_save, sender=Post)
def on_post_created(sender, instance, created, **kwargs):
    if not created: return
    transaction.on_commit(lambda: fanout_post_to_followers.delay(instance.pk))
```

- **decoupled**: signal を受ける側 (timeline app) が posts app を知らなくて良い
- `on_commit` で「commit 後に走る」を保証 ([operating-patterns §10](operating-patterns.md#10-fan-out-on-write--非同期ワーカー--同期-self-entry--soft-delete-instagram) 規律 2)
- **trade-off**: 「どこで何が走るか」が散る → grep で追えるよう regex を整備する規律が要る

### FastAPI: service 関数内で直接記述

```python
# reddit/backend/app/domain/posts/router.py
async def create_post(name, payload, current, session):
    sub = await _resolve_subreddit(name, session)
    initial_hot = hot_score(0, now)              # ← 同期計算
    post = Post(..., hot_score=initial_hot, ...)
    session.add(post); await session.commit()
    return PostResponse.model_validate(post)
```

- **explicit**: 副作用は service 関数の中に直接書く。signal 機構を持たない
- どこで何が走るかが **コードを上から下に読めば分かる**
- **trade-off**: 副作用が増えると router / service が膨らむ。本格的な event-driven にするなら **outbox table + 外部 worker** に切り出す

### 選定軸

`signal + on_commit` は Rails の `after_commit` と同じ思想。Rails 経験者には自然。FastAPI は **「副作用は service に明示的に書く」**を強制する分、書き手の規律が試される。

---

## 4. テストの形

### Django: MySQL service + pytest-django

CI で MySQL container を立てる必要がある。test 時間は MySQL の起動 + migration で 30 秒〜:

```yaml
services:
  mysql:
    image: mysql:8.0
    ports: ["3306:3306"]
- run: python manage.py migrate
- run: pytest
```

`assertNumQueries` で **N+1 を不変条件として固定** ([testing-strategy.md](testing-strategy.md#n1-不変条件試験--djangodrf-の核))。

### FastAPI async: sqlite in-memory + httpx ASGITransport

CI で MySQL 不要。test 時間は数秒:

```python
# tests/conftest.py
TEST_DB_URL = "sqlite+aiosqlite:///:memory:"

@pytest_asyncio.fixture
async def client(sessionmaker):
    app = create_app()
    app.dependency_overrides[db_module.get_session] = lambda: ...
    async with AsyncClient(transport=ASGITransport(app=app)) as ac:
        yield ac
```

詳細: [testing-strategy.md FastAPI 節](testing-strategy.md#fastapi-async-backend-reddit)。

### 選定軸

「test を MySQL 依存にしておきたいか」は派閥問題。Django は MySQL 互換性が高いので CI に MySQL を立てる方が production と近い。FastAPI + sqlite は速いが、`with_for_update()` のような **MySQL 固有挙動が test できない**割り切り。

---

## どちらを選ぶか

### Django (instagram) を選ぶ判断軸

- **管理画面**が初日から欲しい (社内 CRUD ツール、データ投入)
- **per-event 非同期処理 (fan-out)** が中心 → Celery が自然
- **既存の Django エコシステム** (django-allauth / django-rest-framework / django-debug-toolbar) を使いたい
- **CPU bound 処理が多い** → worker thread が直感的

### FastAPI async (reddit) を選ぶ判断軸

- **数百同時接続を 1 worker で**捌きたい (SSE 隣接、polling 多発、軽量 API ゲートウェイ)
- **周期 batch が中心** → APScheduler で broker を増やさず済む
- **型駆動 API 開発** → Pydantic v2 + OpenAPI 自動生成
- **ai-worker (FastAPI) と同じスタック**で開発体験を揃えたい (instagram は Django + FastAPI で 2 種類の Python が混在する)

### 迷ったら

「**周期 batch 中心 / 同時接続が多い → FastAPI async**」「**per-event task 中心 / 管理画面が欲しい → Django**」。

reddit が FastAPI を選んだ理由は ADR 0004 にある。短く言えば:
1. 中核課題 (Hot 再計算 = 周期 batch) が APScheduler に合っていた
2. ai-worker と同じスタックで開発体験を揃えたかった
3. instagram で Django + Celery を体感した後、対照軸として **非同期 I/O + DB-driven scheduler** を経験したかった

---

## 関連

- [coding-rules/python.md](coding-rules/python.md) — (A) ai-worker / (B) Django / (C) FastAPI async の規約
- [operating-patterns.md](operating-patterns.md) — §10 fan-out (Django/Celery), §15 vote 整合 (FastAPI), §16 APScheduler + single-instance
- [testing-strategy.md](testing-strategy.md) — Django pytest / FastAPI async pytest
- [framework-django-vs-rails.md](framework-django-vs-rails.md) — Django ↔ Rails 比較 (本ドキュメントとは別軸)
- instagram ADR: [`instagram/docs/adr/`](../instagram/docs/adr/)
- reddit ADR: [`reddit/docs/adr/`](../reddit/docs/adr/)
