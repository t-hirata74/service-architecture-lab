# テスト戦略

## 基本方針

- **テストは「サービス固有の技術課題が壊れていないか」を守るために書く**。網羅率は目標にしない
- 単体 / 結合 / E2E をレイヤーごとに **重複させずに役割分担** させる
- 「ローカルでブラウザから動作確認できる」ことを完成の定義に含める（CLAUDE.md）。E2E はその担保

---

## レイヤーと責務

| レイヤー | フレームワーク | カバーする範囲 |
| --- | --- | --- |
| Backend 単体 / 結合 (Rails) | **RSpec (rspec-rails) + FactoryBot** | モデル不変条件、controller の入出力、ActionCable 購読 / broadcast |
| Backend 単体 / 結合 (Django) | **pytest-django** | モデル / DRF request / signal / Celery task / N+1 不変条件 |
| Backend 単体 / 結合 (Go) | **標準 `testing` + `go test -race`** | Hub goroutine の concurrency 不変条件 (CSP fan-out / heartbeat eviction / slow consumer drop) |
| Frontend 単体 | （現状なし） | 必要になれば Vitest + React Testing Library を追加 |
| Python 単体 | （現状なし） | ロジックが増えたら pytest を追加 |
| ブラウザ E2E | Playwright | ログインから複数ユーザー / 複数タブを跨ぐ実シナリオ |

E2E が他レイヤーで証明できることを再検証しない。逆に **マルチユーザー / リアルタイム性 / 既読同期** は E2E でしか出ない。

---

## Backend (Rails RSpec)

**共通方針**: Rails backend は RSpec + FactoryBot で運用する。
ディレクトリは rspec-rails 標準:

```text
<service>/backend/spec/
  models/
  requests/             # Controller / API の入出力 (旧 integration / controllers)
  channels/             # ActionCable channel スペック
  jobs/                 # ActiveJob スペック
  factories/            # FactoryBot 定義 (旧 fixtures/*.yml の代わり)
  rails_helper.rb
  spec_helper.rb
```

### 書くもの

- **モデルの不変条件**：例「既読 cursor は単調増加」「アップロード状態機械は不正遷移を拒否」
- **Request 仕様**：認証エラー / 権限 / バリデーション。シリアライズ結果のキー
- **ActionCable**：subscribe 拒否 / 確立 / streaming target / broadcast 内容
- **SSE (`ActionController::Live`)**：`Net::HTTP` 直叩き + 自前 SSE パーサで chunk / event:error / event:done を駆動。`use_transactional_tests = false` + DatabaseCleaner truncation が必要 (perplexity ADR 0005)
- **Integration**：「メッセージ POST → broadcast される」「既読 cursor 進む → UserChannel に流れる」「アップロード → enqueue される」

### 書かないもの

- フレームワーク自体の挙動（Rails の `validates :name, presence: true` を再検証する等）
- 一時的なログ出力 / デバッグ目的のスペック
- 過度なエッジケース（null / 巨大文字列 / 異常型）の網羅

### 実行

```bash
cd <service>/backend
bundle exec rspec                        # 全件
bundle exec rspec spec/requests          # 一部
bundle exec rspec spec/models/video_spec.rb:42   # 行指定
```

### 既存 minitest の扱い

- `slack/backend` は当初 minitest で実装済み。**次に slack に手を入れる時に RSpec へ移行する**
- 新規 / 進行中の Rails backend (`youtube/backend` 等) は最初から RSpec で書く

### Style

- 1 example = 1 振る舞い。`describe` / `context` / `it` で読みやすい階層を作る
- `let` / `let!` は最小限。値が見えなくなる過剰なネストはしない
- `subject` は対象の振る舞いを命名する時のみ使う（`is_expected.to ...` で短くなる時）
- FactoryBot trait を使って状態のバリエーションを表現（例: `:transcoding`, `:published`）

### 実装中に出た落とし穴（リポジトリ固有）

#### MySQL FULLTEXT (ngram) は transactional fixtures だと検索ヒットしない

InnoDB FULLTEXT は **commit 後にしか index に反映されない**。RSpec デフォルトの
`use_transactional_fixtures = true` だと、example 内で `create` した行が
`MATCH ... AGAINST ...` でヒットせず、結果が空になる。

回避策（spec ファイル単位で適用）:

```ruby
RSpec.describe "Videos search", type: :request do
  self.use_transactional_tests = false

  before(:all) do
    [Video, User, Tag, VideoTag].each(&:delete_all)
    @v1 = create(:video, :published, title: "...")
    ...
  end
  after(:all) do
    [Video, User, Tag, VideoTag].each(&:delete_all)
  end
end
```

#### `enqueue_after_transaction_commit` は **ApplicationJob 側に書く**

Rails 8.1 で `config.active_job.enqueue_after_transaction_commit` の **global 指定が deprecated**。
state machine + enqueue の原子性を担保するなら、`app/jobs/application_job.rb` に:

```ruby
class ApplicationJob < ActiveJob::Base
  self.enqueue_after_transaction_commit = true
end
```

詳細は [`coding-rules/rails.md`](coding-rules/rails.md) の「Job の原子的 enqueue」を参照。

#### Active Storage の `analyze_later` がテストログに ffmpeg エラーを残す

ダミーの `StringIO.new("fake-bytes")` を `attach` すると、Active Storage が
動画メタデータ抽出ジョブを enqueue し、ffmpeg が `moov atom not found` で
失敗する。**動作としては無害**（仕様）。ログを抑制したい場合は
`config.active_storage.analyze_later = false` を test 環境に設定するか、
`Video.original.analyze` を呼び出さないテストデータを使う。

#### WebMock は ai-worker 境界の HTTP 越境を遮断する

`spec/rails_helper.rb`:

```ruby
WebMock.disable_net_connect!(allow_localhost: true)
```

これで実 ai-worker への HTTP コールが起きないことを保証する。各 spec で
`stub_request(:post, "#{base}/...")` を明示する。詳細は
[`coding-rules/rails.md`](coding-rules/rails.md) の「ai-worker 境界（共通方針）」を参照。

### OpenAPI 契約検証

REST + OpenAPI を採用するプロジェクト（slack / youtube）では、request spec が
`backend/docs/openapi.yml` のスキーマに **必ず一致**することを committee-rails で検証する。

```ruby
# spec/requests/videos_spec.rb
it "matches OpenAPI schema" do
  get "/videos"
  assert_response_schema_confirm  # committee-rails が openapi.yml と照合
end
```

詳細は [`api-style.md`](api-style.md) を参照。

---

## E2E (Playwright)

```text
slack/playwright/
  tests/
    auth.spec.ts
    realtime-fanout.spec.ts
    read-sync.spec.ts
    summary.spec.ts
    helpers.ts
  playwright.config.ts
```

### 書くもの

- **ブラウザを介さないと出ないシナリオのみ**:
  - ログイン / サインアップ / 未認証リダイレクト
  - 2 BrowserContext を立てて A から送信 → B にリアルタイム配信
  - 既読 cursor の自動進行が複数タブに同期される
  - ai-worker の要約ボタンから結果が表示される

### 設定の注意

- `fullyParallel: false` / `workers: 1`（DB を共有するので serial）
- backend (`:3010`) / frontend (`:3005`) を `webServer` で起動。`reuseExistingServer: true`
- ai-worker を要するスペックは `AI_WORKER_RUNNING=1` 環境変数でガード

### ヘルパ

`tests/helpers.ts` に以下を集約し、各 spec から import:

- `signupViaUI(page, email, password)`
- `loginViaUI(page, email, password)`
- `uniqueEmail()` / `uniqueChannelName()`（時刻 + ランダムで衝突回避）

各 spec で fresh user / channel を作る。fixture を共有しない。

### 実行

```bash
cd slack/playwright
npm test                              # 全件 (HTML reporter)
AI_WORKER_RUNNING=1 npm test          # ai-worker 必要なスペック含む
npx playwright test --ui              # デバッグ
```

---

## Python (ai-worker)

- 現状はモック実装のためテストなし
- ロジックを足したら `pytest` を導入し、CI に追加する
- 導入時は同時に `requirements-dev.txt` を分割

### sqlite + StaticPool で MySQL 不要にする

ai-worker が MySQL を読む構成 (instagram の `/recommend`) では、テストで本物の MySQL を立てずに **sqlite::memory: + StaticPool で同じ SQL を試験**できる:

```python
# instagram/ai-worker/tests/conftest.py
from sqlalchemy.pool import StaticPool

@pytest.fixture
def seeded_engine():
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,    # 1 connection 共有でないと :memory: が別 DB になる
    )
    with engine.begin() as conn:
        conn.execute(text("CREATE TABLE posts (...)"))
        conn.execute(text("INSERT INTO posts VALUES ..."))
    return engine

@pytest.fixture
def client(seeded_engine):
    app.dependency_overrides[get_engine] = lambda: seeded_engine
    yield TestClient(app)
    app.dependency_overrides.clear()
```

SQL が SELECT/JOIN/LIMIT 中心であれば sqlite と MySQL で互換。FULLTEXT (ngram) のような MySQL 固有機能を使うときは別アプローチ ([RSpec FULLTEXT](#mysql-fulltext-ngram-は-transactional-fixtures-だと検索ヒットしない) と同じ問題)。

---

## Django backend (pytest-django)

`instagram/backend/` で確立したパターン。Rails の RSpec と並ぶ位置づけ。

### 書くもの

- **モデルの不変条件** (counter denormalize / soft delete / UNIQUE)
- **Request 仕様** (DRF の認証 / 権限 / バリデーション / pagination)
- **Signal 連鎖** (`Post.save` → fan-out task → `TimelineEntry` 作成)
- **Celery task の冪等性** (`bulk_create(ignore_conflicts=True)` で 2 度呼んでも増えない)
- **N+1 不変条件試験** (下記の専用パターン)

### N+1 不変条件試験 — Django/DRF の核

**「件数で固定する」より「N に依存しない」を不変条件にする**:

```python
# instagram/backend/posts/tests/test_query_count.py
from django.db import connection
from django.test.utils import CaptureQueriesContext

def test_post_list_query_count_is_constant(authed_client, alice, bob):
    seed_posts(bob, 5, liker=alice)
    with CaptureQueriesContext(connection) as ctx_5:
        res = authed_client.get("/posts")
    count_5 = len(ctx_5.captured_queries)

    seed_posts(bob, 15, liker=alice)
    with CaptureQueriesContext(connection) as ctx_20:
        res = authed_client.get("/posts")
    count_20 = len(ctx_20.captured_queries)

    assert count_5 == count_20, (
        f"post list must not N+1; got {count_5} for N=5, {count_20} for N=20"
    )
```

**規律**:

- 固定値 (`assertNumQueries(7)`) で書くと Django/DRF バージョン差で揺れる
- `count_5 == count_20` は **「N に依存しない」という構造的不変条件**
- list endpoint を増やす PR では **必ずこの試験を 1 本書く** ([coding-rules/python.md](coding-rules/python.md))
- `posts.queries.posts_for_viewer()` のような **N+1-safe queryset 関数** + serializer 側の `hasattr` 必須化と組み合わせて、prefetch 漏れを構造的に防ぐ

### `transaction.on_commit` を **テストでは eager 実行する**

pytest-django のデフォルト transaction wrapper は各テストを atomic で囲み rollback で巻き戻す。**この内側では `on_commit` callback が発火しない** (commit が起きないため)。

`monkeypatch` 経由の autouse fixture は pytest-django の処理順で効かないので、**直書き setattr + yield/finally で復元**する:

```python
# conftest.py
@pytest.fixture(autouse=True)
def _on_commit_runs_eagerly():
    """on_commit hook を test 中だけ即時実行する。"""
    from django.db import transaction as dj_tx
    original = dj_tx.on_commit
    dj_tx.on_commit = lambda func, *args, **kwargs: func()
    try:
        yield
    finally:
        dj_tx.on_commit = original
```

これで `Post.save()` → signal → `on_commit(lambda: fanout.delay(pk))` の chain が **同一テスト transaction 内で完結**する。

### Celery `task_always_eager` を **Django settings 側で書き換える**罠

`app.config_from_object("django.conf:settings", namespace="CELERY")` の挙動上、**`celery_app.conf.task_always_eager = True` を直接書いても効かない**:

```python
# ❌ 効かない
celery_app.conf.task_always_eager = True

# ✅ 効く
from django.conf import settings
settings.CELERY_TASK_ALWAYS_EAGER = True
```

Celery は conf アクセス時に毎回 settings から読みに行くため。`os.environ.setdefault("CELERY_TASK_ALWAYS_EAGER", "True")` を conftest top に書く方法は **pytest-django が settings をすでに load した後で**間に合わないこともある。**確実なのは settings 属性の直接代入** (conftest.py の module top で実施)。

### MySQL の test DB 権限を init script で付与する

`pytest-django` は `test_<DATABASE>` を自動 CREATE するが、デフォルトの app ユーザには **`CREATE`/`DROP` 権限がない**。docker-compose の `mysql-init/01-grant-test-db.sql` で grant を init script 化:

```sql
GRANT ALL PRIVILEGES ON `test\_instagram\_%`.* TO 'instagram'@'%';
GRANT CREATE, DROP ON *.* TO 'instagram'@'%';
FLUSH PRIVILEGES;
```

実例: `instagram/infra/mysql-init/01-grant-test-db.sql`。CI では同等の grant ステップをワークフローに直書きする (`instagram-backend` ジョブを参照)。

### Playwright + Django の起動 (Celery worker を立てずに済ませる)

Playwright の `webServer` で Django を起動するとき、**`CELERY_TASK_ALWAYS_EAGER=True` env で起動**すれば fan-out task が Django プロセス内で同期実行される。Celery worker を別プロセスで立てなくて済むので test 安定性が高い:

```ts
// instagram/playwright/playwright.config.ts
const DJANGO_ENV =
  "CELERY_TASK_ALWAYS_EAGER=True DJANGO_DEBUG=True " +
  "CORS_ALLOWED_ORIGINS=http://localhost:3045,http://127.0.0.1:3045";

webServer: [{
  command: `bash -lc 'source .venv/bin/activate && ${DJANGO_ENV} python manage.py runserver 0.0.0.0:3050'`,
  cwd: "../backend",
  url: `${BACKEND_URL}/health`,
  reuseExistingServer: true,
  timeout: 60_000,
}, ...]
```

**trade-off**: production 構成 (Celery worker 別プロセス) と乖離するが、E2E は「ブラウザから golden path が踏めるか」が目的。Celery worker のプロセス分離自体は `instagram-backend` ジョブの pytest で踏まれるので二重保証になる。

---

## FastAPI async backend (reddit) <a id="fastapi-async-backend-reddit"></a>

`reddit/backend/` で確立したパターン。Django pytest と並ぶ Python の **2 系統目**。**SQLAlchemy 2.0 async + aiomysql** を production、**aiosqlite + sqlite in-memory** を test に使う構成。MySQL 不要で 30 件超の test を 7 秒で回せる。

### 構成 — `pytest-asyncio` + `httpx ASGITransport` + sqlite in-memory

```python
# tests/conftest.py
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

import app.models  # noqa  ← 全 mapper を Base.metadata に集約
from app import db as db_module
from app.db import Base
from app.main import create_app

TEST_DB_URL = "sqlite+aiosqlite:///:memory:"

@pytest_asyncio.fixture
async def engine():
    eng = create_async_engine(TEST_DB_URL, future=True)
    async with eng.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    yield eng
    await eng.dispose()

@pytest_asyncio.fixture
async def sessionmaker(engine):
    return async_sessionmaker(engine, expire_on_commit=False, class_=AsyncSession)

@pytest_asyncio.fixture
async def client(sessionmaker):
    app = create_app()
    async def override():
        async with sessionmaker() as s: yield s
    app.dependency_overrides[db_module.get_session] = override
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac
```

### 規律 1: `dependency_overrides` で session を差し替える

production の `get_session` は `aiomysql` 経由で MySQL に繋ぐ。test では `dependency_overrides[get_session] = override` で sqlite session を返すように差し替えれば、**route handler のロジックは無改変**で test できる。

`db.py` に test 専用関数 (`reset_engine_for_tests` 等) を生やさない。dep injection で済ませる。

### 規律 2: SQLAlchemy 2.0 async の `with_for_update()` は sqlite では **no-op**

production (MySQL) では行ロック、test (sqlite) ではノーロック。**ロジック自体は両環境で同じ**:

```python
# vote service: SELECT FOR UPDATE → INSERT/UPDATE → COMMIT
existing = (await session.execute(
    select(Vote).where(...).with_for_update()
)).scalar_one_or_none()
```

sqlite test で UNIQUE 制約 / トランザクション境界 / 相対加算 / idempotent (delta=0) は test できる。**race condition 自体**は sqlite では再現できないので、ロック設計の正しさは ADR + コードレビューで担保する。

### 規律 3: APScheduler は **`ENABLE_SCHEDULER=false`** で起動させない

```python
# tests/conftest.py
os.environ.setdefault("ENABLE_SCHEDULER", "false")
```

`httpx.ASGITransport` は version によって lifespan を起動するので、env で scheduler を無効化する二重保険。ジョブ関数自体は **scheduler を介さず直接 await** して test する ([operating-patterns §16](operating-patterns.md#16-apscheduler-driven-batch--single-instance-constraint-reddit) 規律 3)。

### 規律 4: Hot 式の duplicate test (backend と ai-worker)

reddit Hot 式は `backend/app/domain/posts/ranking.py` (新規 post の初期 hot_score 計算) と `ai-worker/app/ranking.py` (60s 再計算) に **意図的に duplicate** している。**両者が一致することを test で保証**する:

```python
# ai-worker/tests/test_hot_formula.py
def test_ai_worker_and_backend_formula_match():
    spec = importlib.util.spec_from_file_location(
        "backend_ranking",
        Path(__file__).resolve().parents[2] / "backend/app/domain/posts/ranking.py",
    )
    mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
    for s in (-50, -1, 0, 1, 100, 9999):
        assert hot_score(s, dt) == mod.hot_score(s, dt), s
```

**`importlib.util.spec_from_file_location`** で別パッケージの単一ファイルを読み込む。`sys.path` を弄ると `app` 名前空間が衝突するので不可。

### 規律 5: 外部 HTTP は **`respx`** で mock する

```python
import respx, httpx

@respx.mock
async def test_summarize_degraded_on_5xx(client):
    respx.post("http://127.0.0.1:8060/summarize").mock(
        return_value=httpx.Response(503, text="Service Unavailable")
    )
    res = await client.post(f"/posts/{post_id}/summarize")
    assert res.json()["degraded"] is True
```

ai-worker の起動を test で要求しない。graceful degradation の **4 ケース** (success / unreachable / 5xx / 4xx) を respx で全部踏める。

### 規律 6: pytest-asyncio v0.23+ は **`event_loop` fixture を上書きしない**

旧来の以下の pattern は deprecated:
```python
@pytest.fixture(scope="session")
def event_loop():
    loop = asyncio.new_event_loop(); yield loop; loop.close()
```
→ `asyncio_mode = auto` (`pytest.ini`) を入れて、上書きせずに済ませる。

### 書かないもの

- **route ごとの単体 test** — `httpx ASGITransport` 経由の **integration test** で fixture を共有すれば十分
- **race condition の再現** — sqlite で再現不能。ADR + コードレビューで担保し、本物の race は production 観測に任せる
- **scheduler の interval 動作 test** — `time.sleep` で 60s 待つ test は flake のもと。ジョブ関数を直接 await する

### 実行

```bash
cd reddit/backend
source .venv/bin/activate
pytest                    # 全 test
pytest tests/test_votes.py -v
```

CI: `reddit-backend` ジョブで `pip install -r requirements.txt` → `pytest -q`。MySQL service は不要 (sqlite)。

詳細: `reddit/backend/tests/`、ai-worker は `reddit/ai-worker/tests/`。

---

## Go backend (discord) <a id="go-backend-discord"></a>

`discord/backend/` で確立したパターン。Rails RSpec / Django pytest と並ぶ位置づけ。**設計の見どころ (per-guild Hub の goroutine + channel 設計、ADR 0002 / 0003) を 1 ケースずつ縛る**のが中心で、CRUD ハンドラの単体テストは書かない (Playwright E2E が事実上の積分テスト)。

### 書くもの

- **Concurrency 不変条件** — Hub goroutine が `clients` map を専有している前提が壊れていないか
  - register → broadcast で全 client に届く (CSP fan-out)
  - unregister 後は届かない (close 順序)
  - heartbeat timeout で evict される (ADR 0003)
  - slow consumer (Send buffer 満杯) は drop + unregister される (ADR 0002)
  - 同一 user の複数タブで online/offline broadcast が 1 回ずつ (counted-conns)
- **`go test -race ./...` を CI 必須** — 「mutex を持たない設計」の race 不在を構造的に検証
- 純関数の単体テスト (JWT sign/verify など) は **コスト対効果が高ければ追加** する

### 書かないもの

- HTTP handler の入出力試験 — Playwright E2E (`discord/playwright/tests/fanout.spec.ts`) が同等以上を踏む
- DB CRUD — `database/sql` + 生 SQL の Exec/Query は ORM の "framework 自体の挙動" 試験と同じで、書く価値が薄い
- 標準ライブラリの再検証 (chi router の path match / json.Decoder の挙動 等)

### ディレクトリ

```text
discord/backend/
  internal/
    gateway/
      hub.go
      hub_test.go      # Hub の concurrency 不変条件 5 ケース
      client.go
      ...
```

Go の規約として **`*_test.go` は対象ファイルと同じパッケージに置く** (テスト対象の unexported 名にアクセスしたいので `package gateway` のままにする)。

### `*websocket.Conn` を fake する代わりに、Client を直接組み立てる

WebSocket 接続を実際に張ってテストすると、port / handshake / read deadline で flaky になりやすい。Hub から見れば「Client は `Send chan []byte` を持っているだけ」なので、**`Conn = nil` のまま `Client` を直接組み立てて Hub に register する**:

```go
// discord/backend/internal/gateway/hub_test.go
func fakeClient(hub *Hub, userID int64, username string, buf int) *Client {
    if buf <= 0 { buf = clientSendBuffer }
    c := &Client{
        Hub: hub, UserID: userID, Username: username,
        Send: make(chan []byte, buf),
        Stop: make(chan struct{}),
    }
    c.LastHB.Store(time.Now().UnixNano())
    return c
}

func TestHubBroadcastReachesRegisteredClient(t *testing.T) {
    ctx, cancel := context.WithCancel(context.Background())
    defer cancel()
    hub := NewHub(1, 200*time.Millisecond, discardLogger())
    go hub.Run(ctx)

    a := fakeClient(hub, 10, "alice", 0)
    hub.RequestRegister(a)
    time.Sleep(50 * time.Millisecond)             // Run が register を消化する待ち

    payload, _ := MarshalFrame(OpDispatch, EventMessageCreate, MessageCreateData{...})
    hub.Broadcast(payload)
    time.Sleep(50 * time.Millisecond)

    if got := drainKind(a, EventMessageCreate); got != 1 {
        t.Errorf("alice MESSAGE_CREATE = %d, want 1", got)
    }
}
```

**意図**: WritePump を起動しないので `Send chan` を test 側が直接 drain できる。Hub goroutine の `select` が回るだけ待てば検証可能で、**WebSocket protocol を再現せずに Hub の振る舞いだけを縛れる**。

### `time.Sleep` で待つのは妥協、ただし測れる範囲で

「Hub goroutine が register を消化したか」は外から観測できない (chan に送ったら戻るだけ)。`time.Sleep(50ms)` で待つのは必要悪。代わりに:

- **timeout deadline + polling** で「最終的に発火する」イベントを縛る (heartbeat eviction / slow consumer drop は `<-c.Stop` を `select` で待つ)
- **register/broadcast の同期チェック**は `time.Sleep(50ms)` で許容 (CI でも flaky にならない長さに調整)

```go
// 「最終的に Stop が close される」を deadline 付きで待つ
deadline := time.After(time.Second)
for {
    select {
    case <-a.Stop:    return
    case <-deadline:  t.Fatal("client was not evicted on heartbeat timeout")
    case <-time.After(20 * time.Millisecond):
    }
}
```

### `slog.Logger` は `io.Discard` で差し替える

ログを stdout に流さないために、test では `io.Discard` 行きの logger を渡す:

```go
func discardLogger() *slog.Logger {
    return slog.New(slog.NewJSONHandler(io.Discard, nil))
}
```

`Hub.Log` を struct field で持っている設計 ([coding-rules/go.md § 8](coding-rules/go.md)) なら自然に差し替えられる。

### 実行

```bash
cd discord/backend
go test ./...                 # 全件
go test -race ./...           # race 検出付き (CI 必須)
go test -run TestHub ./internal/gateway   # 特定パッケージのみ
go test -v -count=1 ./...     # cache 無効化 + verbose
```

### CI

`.github/workflows/ci.yml` の `discord-backend` ジョブで:

```yaml
- run: go vet ./...
- run: go test -race ./...
```

の 2 段階。`-race` を必須にすることで「Hub goroutine が状態の唯一の owner」という ADR 0002 の前提が **将来の改修で崩れたら CI で気づく**ようにする。

---

## Frontend (Next.js)

- 現状は **lint + 型チェックのみ**（Vitest 未導入）
- 「ロジックが UI から出てきたら」`lib/` レベルでユニットテストを足す。コンポーネント単体を片っ端から testing library で叩くことはしない

---

## CI でのテスト

`.github/workflows/ci.yml`:

- backend: MySQL (+ 必要に応じて Redis) サービス起動 → `db:create db:migrate` → `bundle exec rspec` (slack は移行までの間 `rails test`)
- frontend: `npm run lint` + `npx tsc --noEmit`
- ai-worker: import smoke + uvicorn boot + `/health`

E2E (Playwright) は **現状 CI で動かしていない**（ブラウザバイナリの取得が重い / 学習リポ）。  
将来動かす際は別ジョブで Chromium のみ・必要 spec のみに絞る。

---

## カバレッジ目標

- 数値目標は設定しない。代わりに **ADR で「これを壊さない」と宣言したものは必ずテストで縛る**:
  - ADR 0001 → fan-out E2E (`realtime-fanout.spec.ts`)
  - ADR 0002 → 既読 cursor 単調増加 (model test) + 同期 broadcast (integration test) + 多タブ同期 (E2E)
- ADR を新しく書いたら「これを守るテストはどれか」を ADR 内で言及する

---

## GraphQL プロジェクト固有のテストパターン

github プロジェクト (ADR 0001 / 0002) で確立。GraphQL を採用したら次の 3 つを必ず書く。

### N+1 spec — Dataloader の実効性を縛る

ADR で「Dataloader で N+1 を潰す」と宣言したら、宣言を裏付ける spec を書かないと約束が砕ける。

```ruby
# spec/graphql/n_plus_one_spec.rb
def count_queries
  queries = []
  callback = ->(_, _, _, _, payload) {
    next if payload[:name] == "SCHEMA"
    next if payload[:sql] =~ /\A(SAVEPOINT|RELEASE|BEGIN|COMMIT|ROLLBACK)/i
    queries << payload[:sql]
  }
  ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
  queries
end

it "resolves viewer_permission for N repositories with constant DB queries" do
  queries = count_queries do
    BackendSchema.execute('{ organization(login:"acme"){ repositories { viewerPermission } } }',
                          context: { current_user: user })
  end
  # Loader が効いていれば repo 数 N に対してクエリ本数は定数オーダー
  expect(queries.size).to be <= 10
end
```

実例: `github/backend/spec/graphql/n_plus_one_spec.rb`。

### Field-level authorization spec

「権限不足のフィールドは `null` を返す（HTTP は 200）」という GraphQL の慣習をテストで縛る。

```ruby
it "hides private repository from outsiders (returns null)" do
  body = post_graphql(repo_query, headers: { "X-User-Login" => outsider.login })
  expect(body.dig("data", "repository")).to be_nil  # 404 ではない
  expect(body["errors"]).to be_nil
end
```

実例: `github/backend/spec/requests/graphql_spec.rb`。

### Pundit Scope spec

一覧 (connection / list) 経路は本体 verb spec ほど書き忘れやすい。outside_collaborator のような **base 継承を持たない role** を陽にテストする:

```ruby
it "outside_collaborator does NOT inherit org base — only sees public" do
  user = create(:user)
  Membership.create!(organization: org, user: user, role: :outside_collaborator)
  expect(RepositoryPolicy::Scope.new(user, Repository.all).resolve).to contain_exactly(public_repo)
end
```

実例: `github/backend/spec/policies/repository_policy_scope_spec.rb`。

### 連番採番 (`with_lock`) の限界

transactional fixtures は同じ DB connection を共有するので、threads を並行起動しても本物の lock 競合は再現できない。**意図確認に留める**:

```ruby
it "uses with_lock to serialize concurrent updates" do
  expect_any_instance_of(RepositoryIssueNumber).to receive(:with_lock).and_call_original
  IssueNumberAllocator.next_for(repository)
end
```

真の並行性を見たい場合は別 DB / システムテストで `:truncation` strategy にする (学習リポでは不要)。
実例: `github/backend/spec/services/issue_number_allocator_spec.rb`。
