# ADR 0002: Hub の goroutine + channel 実装パターン

## ステータス

Accepted（2026-05-04）

## コンテキスト

ADR 0001 で **per-guild Hub goroutine** という骨格を決めた。本 ADR は **Hub の内部実装をどう書くか** を扱う。

Hub は内部状態 (`subscribers` の集合) を保持し、複数 goroutine から以下のイベントを受ける:

- **register**: 新しい client が IDENTIFY を完了した
- **unregister**: client が ws 切断 / heartbeat 失敗で退場した
- **broadcast**: REST POST /messages 経由で新しいメッセージが入った
- **presence_update**: ハートビート監視ループが「online → offline」遷移を検知した

これらの **同時アクセスをどう捌くか**が Go の流儀の選びどころ:

- (A) `sync.RWMutex + map` で lock を取る (mutex 流)
- (B) **single goroutine + channel + select** (CSP 流 / "Don't communicate by sharing memory")

slack の Rails ActionCable は (A) 寄り (Redis pub/sub の subscribe loop が thread-safe な map 操作)。**Go の流儀は (B)** であり、本プロジェクトの学習対象は **「Go らしい concurrency パターン」** を実装で体感すること。

制約:

- 1 Hub あたり subscribers は数十〜数百を想定 (1 ギルドのオンラインメンバ)
- broadcast 頻度はチャットなので毎秒数件オーダー
- メッセージ順序は **同 client から見て monotonic** であれば十分 (グローバル序列は要求しない)

## 決定

**「Hub は単一 goroutine で `select { case <-register: ; case <-unregister: ; case msg := <-broadcast: ... }` で全イベントを処理する」** を採用する。

```go
type Hub struct {
    guildID   int64
    register   chan *Client
    unregister chan *Client
    broadcast  chan *Event
    quit       chan struct{}

    // Hub goroutine 専有 (mutex 不要)
    clients    map[*Client]struct{}
    presences  map[int64]Presence  // user_id -> Presence
}

func (h *Hub) Run(ctx context.Context) {
    for {
        select {
        case c := <-h.register:
            h.clients[c] = struct{}{}
            ...
        case c := <-h.unregister:
            delete(h.clients, c)
            close(c.send)
        case ev := <-h.broadcast:
            for c := range h.clients {
                select {
                case c.send <- ev.Payload:
                default:
                    // slow consumer: send buffer 満杯 → unregister
                    delete(h.clients, c)
                    close(c.send)
                }
            }
        case <-ctx.Done():
            return
        }
    }
}
```

- **`clients` map は Hub goroutine だけが触る** (mutex 不要)
- **`Client.send` は buffered chan** (例: cap=64)。slow consumer (network 遅延 / フリーズ) が Hub 全体を blocking しないために、`send <-` は **non-blocking select + default で drop** する規律
- drop された client は **強制 unregister + close(send)**。再接続前提
- 全 chan は **closed-channel-safe** な操作のみ行う (close は Hub goroutine からのみ)
- Hub の停止は `ctx.Done()` で誘導、`quit` chan は使わない (context 統一)

## 検討した選択肢

### 1. single goroutine + select pattern ← 採用

- 利点: **Go の流儀通り**。`clients` map は 1 goroutine 専有なので mutex 不要、deadlock リスクが構造的に消える
- 利点: select の各 case が 1 つの責務 (register/unregister/broadcast/timeout) で**ファイルを読めば全パターンが見える**
- 利点: テストが書きやすい (Hub.Run を別 goroutine で起動 + chan に送る + 結果を観測)
- 欠点: select 内処理がブロックすると **他のイベントも詰まる**。broadcast 内 loop で send chan が満杯 → blocking すると他 client の register も止まる → これは **non-blocking select + default で drop** で回避する

### 2. sync.RWMutex + map

```go
type Hub struct {
    mu      sync.RWMutex
    clients map[*Client]struct{}
}
func (h *Hub) Broadcast(payload []byte) {
    h.mu.RLock()
    defer h.mu.RUnlock()
    for c := range h.clients {
        c.send <- payload
    }
}
```

- 利点: 直感的、API が普通の関数呼び出し (chan を露出しない)
- 利点: 並行 read が RLock で性能高い
- 欠点: **Go らしさが薄れる**。本プロジェクトの学習対象 (CSP) と外れる
- 欠点: send chan への blocking write が RLock を保持したまま起きると、他の Lock 取得を阻む chain がある
- 欠点: 「Hub に追加メソッドを足すたびに lock 順序を考える」コストが残る

### 3. Actor model with mailbox (proto.actor 等)

- 利点: 純粋な actor model でテスト容易性高い
- 欠点: 外部 lib 依存 + Go の流儀から外れる (chan で十分)
- 欠点: 本プロジェクトの学習対象 (Go 標準 concurrency) と直交

### 4. sync.Map

- 利点: lock-free な map
- 欠点: 「broadcast で全 client に送る」という iterate が前提のワークロードに `sync.Map` は不向き (Range は弱い保証)
- 欠点: select との統合ができない (chan が無いので Hub の他イベントとの調停ができない)

### 5. atomic + immutable map (copy-on-write)

- 利点: 完全 lock-free
- 欠点: register/unregister 頻度が高いとコピー多発でメモリ飛ぶ
- 欠点: 過剰最適化、本 MVP スコープを超える

## 採用理由

- **学習価値**: Go の **CSP 流 concurrency** ("share memory by communicating") を実装で体感する。Rails ActionCable / Sidekiq とは異なる思想を実コードで残せる
- **アーキテクチャ妥当性**: 標準ライブラリ (`gorilla/websocket` の例) も同パターン。Go コミュニティのデファクト
- **責務分離**: Hub goroutine が `clients` map の唯一の owner。他 goroutine は chan 経由でしか触れないので、**「誰がこの map を変えうるか」がコードを見て即座に分かる**
- **テスタビリティ**: Hub に対する全操作が chan 送受信なので、test では `hub.register <- client` のように **同期的に 1 イベントを注入**してから assertion を書ける

## 却下理由

- **RWMutex + map**: Go の流儀から外れる、本プロジェクト学習対象とズレる
- **Actor model**: 外部 lib 依存、chan で十分
- **sync.Map**: iterate workload に不向き、select 統合不能
- **immutable + atomic**: 過剰最適化

## 引き受けるトレードオフ

- **send chan buffer サイズの選定**: cap=64 で開始。`bench` で実測してから派生 ADR で根拠を残す。slow consumer を **発見したら drop** する規律で安全側に倒す
- **drop による message loss**: Hub.broadcast → client.send が満杯なら drop + unregister。**at-least-once は保証しない**。クライアントは「切断検知 → REST GET で取り直す」モデル前提 (派生 ADR 候補: at-least-once via outbox + replay token)
- **Hub goroutine が CPU bound 処理を入れたら全停止**: broadcast 内では payload encode 済み []byte をそのまま流すだけ、JSON marshal 等は **送り手側 (caller)** で済ませる規律
- **close(send) の race**: unregister case 内でのみ close する規律で write-after-close を防ぐ。test で `go test -race` を必須化
- **Hub goroutine 数 = 同時アクティブ guild 数**: 1 万 guild が同時 active なら 1 万 goroutine。Go の goroutine は 2KB stack で安いが、broadcast traffic が薄い Hub も常時居座る。**inactive な Hub の lazy 停止 (空 client が一定時間続いたら自身を unregister) は派生 ADR**
- **close 順序の規律**: `unregister` で `delete(clients, c) → close(c.send)` の順序を厳守。逆だと writer が close 済み chan に書く panic。`Client.send` への書き込みは Hub goroutine のみ + non-blocking select + default + delete + close で線型化

## このADRを守るテスト / 実装ポインタ（Phase 3 で実装）

- `discord/backend/internal/gateway/hub.go` — Hub struct + Run loop + select
- `discord/backend/internal/gateway/client.go` — Client struct + readPump / writePump + send chan
- `discord/backend/internal/gateway/hub_test.go`:
  - register → broadcast → 受信される
  - unregister 後の broadcast は届かない
  - slow consumer (send 満杯 + drop) が発生しても Hub が止まらない
  - close(quit) で Hub goroutine が抜ける
  - `go test -race` で race condition 検出
- `discord/backend/internal/gateway/registry.go` — `map[guildID]*Hub` (これも Hub registry goroutine で管理)

## 関連 ADR

- ADR 0001: 単一プロセス per-guild Hub の骨格 (本 ADR の親)
- ADR 0003: プレゼンス heartbeat (Hub の `presences` map と broadcast 経路)
- ADR 0008 (派生予定): inactive Hub の lazy 停止
- ADR 0009 (派生予定): at-least-once delivery (transactional outbox + replay)
