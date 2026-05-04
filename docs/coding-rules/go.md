# Go コーディング規約 / 選定判断

`discord/backend/` で実際に採用している規約と、**「いつ Go を選ぶか」「Go で何を学ぶか」** の判断軸を共通ルールとしてまとめる。Rails / Django / FastAPI を含めた選定の中で **Go の役回りを明確にする** のが目的。

---

## 1. いつ Go を選ぶか (技術判断)

Go は「Rails/Django で書ける CRUD」の代わりにはしない。**Go でしか自然に書けない問題**が中心テーマのときだけ採用する。

### Go を選ぶ基準

以下のうち **2 つ以上**当てはまるなら Go の出番。

| 基準 | 例 | Rails/Django との比較 |
| --- | --- | --- |
| **長寿命の同時接続が数千〜数万** (WebSocket / SSE / gRPC streaming) | Discord WS gateway / Uber driver location stream | Rails ActionCable は thread / Redis pub-sub で書けるが、**プロセス毎の接続数で頭打ち**。Go は goroutine 2KB/conn で 10k+ |
| **CPU 並行 + 状態共有** が中心ロジック | per-guild Hub の broadcast / 空間索引の更新 | Ruby/Python は GIL で本物の並行が出ない。Go は **CSP (channel + select) を言語標準で持つ** |
| **メモリ常駐の状態機械** が DB より速いレイテンシ要件 | Discord の per-guild presence / Uber の geo-index | Rails で書くと Redis + 別 worker process に分割されがち。Go は **single binary + in-memory** で完結する |
| **起動が速い / バイナリ 1 個で配布したい** | サイドカー / CLI / shipping コンテナの軽量化 | Rails は boot が秒オーダー、Python は venv が要る |

### Go を選ばない基準

以下に当てはまるなら Rails / Django のほうが速い。

- **CRUD + admin + form validation が中心** — Rails の generator / Active Record / strong params に勝てない
- **複雑な権限グラフ (role / scope / per-resource ACL)** — Pundit / cancancan / GraphQL の resolver で書く方が宣言的
- **ER モデルが頻繁に変わる** — `database/sql` + 生 SQL は migration / association 変更のコストが高い
- **学習対象が「フレームワークの慣習を体得する」** — Rails の Convention over Configuration を捨てると意味が減る

### 本リポでの Go 採用例

- **discord (Phase 5 完了)** — WebSocket fan-out + per-guild Hub + presence。Slack (Rails ActionCable) との **対比学習**を意図的に置いている
- **uber (予定)** — 並行 + 空間索引 + 状態機械。地理データ更新の write が高頻度

両者とも **「Rails で書くと不自然になる中核」** を Go の流儀に置き換えることが学習対象。

---

## 2. 技術スタック (discord/backend で確立)

- **Go 1.24** / `go.mod` で依存管理
- **HTTP**: [`go-chi/chi`](https://github.com/go-chi/chi) + `go-chi/cors` — net/http 互換、middleware が薄い
- **WebSocket**: [`gorilla/websocket`](https://github.com/gorilla/websocket) — net/http のハイジャック前提
- **DB**: `database/sql` + `go-sql-driver/mysql` — **ORM は使わない**。生 SQL を `internal/store/store.go` にまとめる
- **JWT**: `github.com/golang-jwt/jwt/v5` (HS256)
- **bcrypt**: `golang.org/x/crypto/bcrypt`
- **ロギング**: 標準 `log/slog` (JSON handler)
- **テスト**: 標準 `testing` + `go test -race`
- **マイグレーション**: 自前の `cmd/server/migrate` + `embed.FS` で `*.sql` を埋め込む（外部 lib なし）

### 入れない gem 相当 / 入れる基準

- ❌ ORM (gorm / ent) — 学習対象が「生 SQL を database/sql で書く」なので意図的に避ける
- ❌ DI コンテナ (wire / fx) — main.go で素直に組み立てる
- ❌ HTTP middleware bundle (gin / echo) — chi で十分。標準 net/http 互換が大きい
- ✅ chi / gorilla/websocket / golang-jwt — **学習対象に直接寄与する** + Go コミュニティ標準
- ✅ `golang.org/x/...` — 準標準扱い

---

## 3. ディレクトリ構成 (Go の流儀)

```text
discord/backend/
  cmd/
    server/
      main.go          # エントリポイント。組み立て + signal handling
      migrate/         # サブコマンド (cmd/server/migrate を独立 main に)
  internal/            # internal/ 配下は外部から import 不能 (Go の機能)
    api/               # HTTP handler (chi router)
    auth/              # JWT / bcrypt
    config/            # 環境変数ロード
    gateway/           # WebSocket + Hub + Client + Registry
    store/             # database/sql ラッパ (生 SQL)
  go.mod / go.sum
```

### 規律

- **`internal/` を最大限使う** — パッケージ可視性を Go 言語機能で縛る。Rails の `app/services/` のような暗黙のレイヤ分けより強い保証
- **`cmd/<binary>/main.go` 1 ファイル = 1 実行ファイル** — `go build ./cmd/server` で 1 バイナリ。サブコマンドは別 `cmd/<binary>/<sub>/main.go`
- **package 名 = ディレクトリ名 = 単数形** — `gateway` (× gateways)、`store` (× stores)
- **`type` を機能で分けず、ドメインで分ける** — `gateway/hub.go` `gateway/client.go` `gateway/protocol.go` のように **1 ファイル = 1 概念**

---

## 4. エラーハンドリング

Go はエラーを「値」として戻り値で扱う。Rails の例外 + `rescue_from` モデルとは設計思想が違う。

### 規律

- **`error` は最後の戻り値**。多値で `(T, error)` を返す
- **`errors.Is(err, store.ErrNotFound)` で判定**。文字列マッチ (`err.Error() == "..."`) は NG
- **公開センチネル**: パッケージ境界に出すエラーは `var ErrXxx = errors.New("...")` で公開
  - 例: `store.ErrNotFound`
- **wrap は `fmt.Errorf("...: %w", err)`** — `%w` で chain。caller で `errors.Is` / `errors.As` が効く
- **panic は使わない** — config 検証など起動時 fatal だけ `panic` 容認 (例: `cfg.MustValidate()`)
- **HTTP handler は `http.Error(w, msg, code)` で素直に返す** — Rails の `rescue_from` のような global hook は組まない

### Bad

```go
if err.Error() == "not found" { ... }       // 文字列依存
if err != nil { panic(err) }                 // 流せない
```

### Good

```go
u, err := s.UserByID(ctx, id)
if errors.Is(err, store.ErrNotFound) {
    http.Error(w, "user not found", http.StatusNotFound); return
}
if err != nil {
    log.Error("fetch user", slog.Any("err", err))
    http.Error(w, "internal", http.StatusInternalServerError); return
}
```

---

## 5. Concurrency パターン (Discord で確立)

Go の核は goroutine + channel。**`sync.Mutex` で済ませる前に CSP で書けないか考える**。

### 5.1 Single-goroutine ownership (CSP 流)

ある状態 (map / slice / counter) を **1 goroutine の専有**にし、外部からは channel 経由でしか触らせない。**mutex なしで race-free**。

```go
type Hub struct {
    register, unregister chan *Client
    broadcast            chan []byte
    clients              map[*Client]struct{}  // Run goroutine 専有 (mutex 不要)
}

func (h *Hub) Run(ctx context.Context) {
    for {
        select {
        case c := <-h.register:    h.clients[c] = struct{}{}
        case c := <-h.unregister:  delete(h.clients, c)
        case msg := <-h.broadcast: for c := range h.clients { ... }
        case <-ctx.Done():         return
        }
    }
}
```

**いつ使う**:
- 状態が 1 つに集約 + イベント源が複数 (network read / timer / API request)
- mutex の lock 順序や deadlock を考えたくない
- テストで「1 イベントを注入 → 観測」したい (channel send だけで駆動できる)

実例: `discord/backend/internal/gateway/hub.go` (ADR 0002)

### 5.2 Non-blocking send + drop で slow consumer を吸収

broadcast loop で `c.Send <- payload` を blocking で書くと、**1 つの遅い client が Hub 全体を止める**。`select { case c.Send <-: ; default: }` で **drop して unregister** する規律。

```go
func (c *Client) trySend(payload []byte) bool {
    select { case <-c.Stop: return false; default: }
    select {
    case c.Send <- payload: return true
    default:                return false  // buffer 満杯 → caller が drop
    }
}
```

drop された client は **強制 unregister + close(Stop)**。WebSocket は再接続前提なので at-least-once は保証しない。

実例: `discord/backend/internal/gateway/hub.go:fanout` + `client.go:trySend`

### 5.3 `context.Context` で停止伝播

- **goroutine を起動するときは `ctx context.Context` を受け取る**。停止指示は `<-ctx.Done()` で受ける
- 自前の `quit chan struct{}` は **使わない** (context に統一)
- HTTP handler は `r.Context()` をそのまま下流に流す。タイムアウトと cancel が伝播する
- **長寿命の WebSocket は middleware.Timeout の外に置く** (chi の `Group` を分ける)

```go
root.Get("/gateway", gw.HandleGateway)              // timeout なし (long-lived WS)
root.Group(func(r chi.Router) {
    r.Use(middleware.Timeout(120 * time.Second))    // REST はタイムアウト
    r.Mount("/", h.Routes())
})
```

実例: `discord/backend/cmd/server/main.go`

### 5.4 `sync/atomic` は単一 counter 用に限定

複数フィールドをまとめて読み書きする場合は atomic では足りない。`atomic.Int64` は **「heartbeat の最終時刻」のような単一 counter** に限定する。

```go
type Client struct {
    LastHB atomic.Int64   // readPump が write、Hub goroutine が read
}
```

実例: `discord/backend/internal/gateway/client.go:Client.LastHB`

### 5.5 close 順序の規律

- **channel の close は producer 側からのみ**
- **`sync.Once` で idempotent な close** を作る (二重 close は panic)

```go
func (c *Client) Close() {
    c.closeOnce.Do(func() { close(c.Stop) })
}
```

`Stop` は close-only signal、`Send` は close せず Stop で writer 側を抜けさせる。**「close 済み chan に write して panic」を構造的に防ぐ**ため、`Send` への write は常に `select` で `Stop` も同時待ちする。

実例: `discord/backend/internal/gateway/client.go`

---

## 6. HTTP / API レイヤ (chi)

### Router 構成

```go
root := chi.NewRouter()
root.Use(middleware.RealIP, middleware.RequestID, middleware.Recoverer)
root.Use(chicors.Handler(...))

root.Get("/gateway", gw.HandleGateway)              // long-lived は timeout 外
root.Group(func(r chi.Router) {
    r.Use(middleware.Timeout(120 * time.Second))
    r.Mount("/", h.Routes())
})
```

### Handler の書き方

- **handler は `func(http.ResponseWriter, *http.Request)`** が原型。chi の `chi.URLParam(r, "id")` でパス param 取得
- **JSON 入出力は `json.NewDecoder` / `json.NewEncoder`** で wrap せず標準を使う
- **エラーは `http.Error(w, msg, code)`**。共通の error response シリアライザは作らない (handler 数本なら直書きで十分)
- **認証は middleware**。`r.Context()` に user を載せて handler から `api.UserFrom(ctx)` で取り出す

実例: `discord/backend/internal/api/handler.go` + `internal/api/context.go`

---

## 7. DB レイヤ (database/sql + 生 SQL)

ORM を使わず、**`internal/store/store.go` に SQL を集約**。

### 規律

- **`*sql.DB` は process 全体で 1 つ**。`SetMaxOpenConns` / `SetMaxIdleConns` / `SetConnMaxLifetime` を必ず明示
- **すべて `ExecContext` / `QueryContext` / `QueryRowContext`** (context なし版は禁止)
- **トランザクションは `BeginTx` + `defer tx.Rollback()` + 明示 `tx.Commit()`** で書く
- **`sql.ErrNoRows` は store 層で `ErrNotFound` に翻訳**して返す。caller は `errors.Is(err, store.ErrNotFound)` で判定
- **`?` placeholder で必ず bind**。文字列連結 SQL は禁止
- **`json:"-"` で password_hash を漏らさない** — struct tag で API 応答から除外

```go
func (s *Store) CreateGuildWithOwner(ctx context.Context, name string, ownerID int64) (int64, error) {
    tx, err := s.DB.BeginTx(ctx, nil)
    if err != nil { return 0, err }
    defer tx.Rollback()
    res, err := tx.ExecContext(ctx, `INSERT INTO guilds (name, owner_id) VALUES (?, ?)`, name, ownerID)
    if err != nil { return 0, err }
    id, _ := res.LastInsertId()
    if _, err := tx.ExecContext(ctx, `INSERT INTO memberships (guild_id, user_id, role) VALUES (?, ?, 'owner')`, id, ownerID); err != nil {
        return 0, err
    }
    return id, tx.Commit()
}
```

### マイグレーション

外部 lib (golang-migrate / goose) を入れず、自前で `embed.FS` + `*.sql` 連番ファイルを使う。**Go の `embed` だけで十分**。

実例: `discord/backend/cmd/server/migrate/`

---

## 8. ロギング (log/slog)

- **`log/slog` を使う** (Go 1.21+ 標準)。zap / zerolog は学習対象に対してオーバー
- **JSON handler を本番想定で固定** — `slog.NewJSONHandler(os.Stdout, ...)`
- **構造化フィールドで渡す** — `log.Info("hub register", slog.Int64("guild_id", g), slog.Int64("user_id", u))`
- **`fmt.Sprintf` で組み立てない**。grep より構造化検索 (CloudWatch Insights / Loki) が効く前提
- **logger を struct field で持ち回す** — package global にしない (テスト時に `slog.New(slog.NewJSONHandler(io.Discard, nil))` で差し替え可能)

```go
type Hub struct {
    Log *slog.Logger
}
```

---

## 9. 設定 (環境変数)

- **`internal/config/config.go` で `os.Getenv` を集約**
- **`Load()` で読み、`MustValidate()` で必須項目を panic** — 起動時 fatal は構造的に許容
- **デフォルト値は dev 用のリテラル** — 本番ではすべて env で上書き想定

```go
type Config struct {
    DatabaseURL         string
    JWTSecret           string
    AIWorkerURL         string
    AIInternalToken     string
    HeartbeatIntervalMs int
}
```

---

## 10. Lint / Format

- **`gofmt` (= `go fmt ./...`)** — 議論しない。tab indent / import 並び順は標準
- **`go vet ./...`** を CI 必須 — 単純 bug を弾く
- **`golangci-lint`** はまだ導入していない (Discord MVP では `vet` + `test -race` で十分と判断)。導入時は `errcheck / govet / staticcheck / ineffassign` の 4 つから始める
- **import grouping**: 標準ライブラリ → 外部 → 自プロジェクト の 3 ブロック (gofmt + goimports が自動)

---

## 11. テスト

詳細は [`testing-strategy.md`](../testing-strategy.md#go-backend-discord) を参照。要点だけ:

- 標準 `testing` で十分。testify は導入していない
- `go test -race ./...` を CI 必須 (concurrency パターンの race 検出)
- **設計の見どころ (CSP Hub / non-blocking drop / heartbeat eviction / multi-tab presence) を 1 ケースずつ縛る**。網羅率は目標にしない
- WebSocket の `*Conn` を fake する代わりに、**`Client` を `Conn` なしで直接組み立てる** (`fakeClient` ヘルパ)。Hub goroutine から見れば Send chan に書ければ十分

実例: `discord/backend/internal/gateway/hub_test.go` (5 ケース)

---

## 12. Rails / Django との対比 (学習用早見表)

| テーマ | Rails | Django | Go (discord) |
| --- | --- | --- | --- |
| HTTP routing | `config/routes.rb` (DSL) | `urls.py` (list) | chi router (`r.Get(...)`) |
| ORM | Active Record | Django ORM | **使わない** (database/sql + 生 SQL) |
| Concurrency | thread + GIL / Sidekiq | thread + GIL / Celery | **goroutine + channel** (CSP) |
| Realtime | ActionCable + Redis pub-sub | Channels + Redis | **gorilla/websocket + per-guild Hub goroutine** |
| State sharing | Redis / DB | Redis / DB | **in-memory map (1 goroutine 専有)** |
| Background job | Solid Queue / Sidekiq | Celery | **goroutine + channel** (常駐) or 別 binary |
| Error handling | `rescue` + `rescue_from` | `try/except` + middleware | **戻り値 `error` + `errors.Is`** |
| DI / Config | `Rails.application.config` | `settings.py` | main.go で組み立て (DI lib なし) |
| Migration | `rails db:migrate` (AR) | `manage.py migrate` | **embed.FS + 自前 runner** |
| Test | RSpec + FactoryBot | pytest-django | 標準 `testing` + `go test -race` |

**学びの中心**: Rails / Django で書くと「Redis + 別 worker process」になるところを、**Go では single binary + in-memory + goroutine で書ける**。これが Go の存在意義であり、本リポで Go を採用する唯一の理由。

---

## 関連ドキュメント

- [discord/docs/adr/](../../discord/docs/adr/) — Go 実装の設計判断 (per-guild Hub / CSP pattern / heartbeat / JWT)
- [operating-patterns.md § 13](../operating-patterns.md) — single-process Hub goroutine + CSP fan-out の運用知
- [testing-strategy.md § Go backend](../testing-strategy.md#go-backend-discord)
- [coding-rules/rails.md](rails.md) / [coding-rules/python.md](python.md) — 他言語の対応版
- [service-architecture-lab-policy.md](../service-architecture-lab-policy.md) — プロジェクト方針
