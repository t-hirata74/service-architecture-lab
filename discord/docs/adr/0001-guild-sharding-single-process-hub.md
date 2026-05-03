# ADR 0001: ギルド単位シャーディング + 単一プロセス Hub

## ステータス

Accepted（2026-05-04）

## コンテキスト

`discord` プロジェクトの中核技術課題は **「数千クライアントが常時接続する WebSocket gateway をどう設計するか」**。実 Discord は数百万接続を捌くため **ギルド ID で shard 化**された複数 gateway プロセスを持ち、各 shard がその shard owns するギルド集合の fan-out を担当する。

リポジトリ全体方針 (CLAUDE.md「言語別バックエンド方針」) で discord プロジェクトの目的は:

- **Go の高並行性 (goroutine + channel)** を実装で体感する
- **WebSocket fan-out + ギルド単位シャーディング** の設計を学ぶ
- 既に slack で実装済みの **Rails ActionCable + Redis pub/sub** と対比する

slack ([slack/docs/adr/0001](../../../slack/docs/adr/)) は:
- Rails ActionCable + Redis pub/sub
- Channel 単位の broadcast (`stream_for room`)
- Worker process が複数立っても Redis 経由で fan-out 共有

discord は **「同じ fan-out 課題を Go で解くとどうなるか」** が学習対象。

制約:

- ローカル完結 (MySQL のみ、**Redis 不使用**)
- ローカル想定スケール (1 process / 数百接続) を前提
- 学習対象は **「単一プロセスでの per-guild Hub goroutine」**。実 Discord 規模の cross-process sharding は派生 ADR で扱う

## 決定

**「単一 Go プロセスで、ギルドごとに Hub goroutine を持つ。クライアントは IDENTIFY で guild_id を申告し、対応する Hub に register される」** を採用する。

- **`Gateway` プロセス** = HTTP (REST) + WebSocket (`/gateway`) を 1 つの Go プロセスで提供
- **`Hub` per guild**: ギルドごとに 1 つの goroutine が立ち、そのギルドの **subscribers (clients) / broadcast / register / unregister** を一手に管理
- **`HubRegistry`**: `map[guild_id]*Hub` を保持する process global。なければ lazy 起動
- **メッセージ flow**:
  1. Client が WS 接続 + IDENTIFY (JWT + guild_id)
  2. Gateway が認証 + ギルド membership 確認 → 該当 Hub に register
  3. REST POST /channels/:id/messages → DB INSERT → 該当 guild の Hub.broadcast に送信
  4. Hub goroutine が select で受け、subscribers の send chan に payload を流す
- **Redis pub/sub は不採用** (単一プロセス前提なので channel で十分)
- **shard 化は将来 ADR**: 「multi-process gateway + Redis pub/sub 経由 cross-shard fan-out」を派生 ADR 候補として残す

## 検討した選択肢

### 1. 単一プロセス + per-guild Hub ← 採用

- 利点: Go の goroutine + channel が直接効く題材。最小依存 (Redis 不要)
- 利点: ギルド単位のシャーディング思想を **コードの形で残せる** (将来 multi-shard に拡張する道筋が見える)
- 利点: slack (Rails + Redis pub/sub) との対比が「同じ問題を別言語で解く」として明示できる
- 欠点: 単一プロセスの限界 (~10k concurrent ws 接続 / メモリ上限)。学習用途では問題なし

### 2. 単一プロセス + 1 つの global Hub

- 利点: 最も単純
- 欠点: **全クライアントに全イベントが broadcast** されるか、Hub 内で guild filter する必要がある。filter コストが O(N) で Hub に集中する
- 欠点: 「ギルド単位シャーディング」の学習目的と外れる

### 3. 単一プロセス + per-channel Hub

- 利点: チャンネル粒度の broadcast がシンプル
- 欠点: チャンネル数 × ギルド数で goroutine 数が爆発する (1 ギルドに 50 チャンネルなら 50 倍)
- 欠点: 「ギルド単位 shard」の発想と粒度が合わない (本物 Discord は guild_id で shard)

### 4. multi-process gateway + Redis pub/sub fan-out

- 利点: 実 Discord に最も近い
- 利点: 1 プロセス当たりの接続数限界を緩和できる
- 欠点: **本 ADR スコープを超える**。Redis 依存が増え、cross-shard delivery 順序保証 / at-least-once などの論点が膨らむ
- 欠点: 学習対象が「Go の concurrency」から「分散システム」に逸れる
- **派生 ADR で扱う**

### 5. NATS / Kafka 経由の event bus

- 利点: イベント駆動の設計を学べる
- 欠点: ローカル完結方針からの依存追加が大きい (Kafka は数 GB メモリ食う)
- 欠点: discord の本質である「WebSocket gateway 自体の構造」から逸れる

### 6. Channels 標準 chan ではなく `sync.Map` + RWMutex 直接操作

- 利点: select の制約 (1 goroutine が単一 select で sequential 処理) を回避できる
- 欠点: lock 順序の規律が必要、deadlock リスクが上がる
- 欠点: Go の流儀から外れる ("Don't communicate by sharing memory; share memory by communicating")
- **Hub の内部実装方針として ADR 0002 で詳しく扱う**

## 採用理由

- **学習価値**: Go の goroutine + channel + select という言語の中心機能を、現実的な題材 (WebSocket gateway) で使える。slack (Rails ActionCable + Redis) との対比で「2 つの言語 / FW で同じ問題をどう解いたか」がコードレベルで残る
- **アーキテクチャ妥当性**: 実 Discord も初期は単一プロセス + 内部 in-memory ゲートウェイから始め、スケールに応じて shard 分割した。本プロジェクトは「初期形」を実装する位置づけ
- **責務分離**: REST API (CRUD) と WebSocket gateway (fan-out) を **同一プロセス**に同居させるが、`internal/gateway` パッケージで境界を引く。将来 gateway を別 binary に切り出す際の境界を最初から見える形で
- **将来の拡張性**: per-guild Hub + HubRegistry の構造は、各 Hub が別プロセスに動いても interface が変わらない。multi-shard 化の派生 ADR で「Hub の register 経路を Redis pub/sub に差し替える」だけで済む

## 却下理由

- **global Hub**: ギルド単位シャーディングの学習目的とズレる。filter コストが Hub に集中
- **per-channel Hub**: goroutine 数爆発、ギルド単位 shard の粒度と不整合
- **multi-process + Redis**: 本 ADR スコープ超え、Go concurrency より分散システムが主題に
- **NATS / Kafka**: 依存重すぎ、本質から逸れる
- **sync.Map + RWMutex**: ADR 0002 で実装パターンとして再検討

## 引き受けるトレードオフ

- **単一プロセス限界**: 接続数 / メモリ / 単一プロセス障害が即サービス停止。MVP では許容
- **永続化と broadcast の境界が緩い**: メッセージは DB INSERT → in-process Hub.broadcast。INSERT は成功したが broadcast が落ちた場合、subscribers は次回 reconnect で REST から取り直す (transactional outbox は導入しない、派生 ADR 候補)
- **再接続時の差分配信なし**: クライアントが ws 切断中に流れたメッセージは「REST GET /channels/:id/messages?after=last_id」で取り直す前提。op `RESUME` 相当は実装しない (派生 ADR)
- **shard 切替時のセッション継続性**: multi-shard に拡張する時は client が切断・再接続を要する。本 ADR では考慮対象外
- **メモリ上の subscribers リスト消失**: プロセス再起動で全 ws 接続が切れる。client 側は再接続戦略を持つ前提
- **slack との重複と差別化**: 「WebSocket fan-out」は slack と同じ題材だが、focus は **「Go の concurrency primitives」 vs 「Rails ActionCable + Redis pub/sub」**。同じ問題を別スタックで解く比較学習が成果

## このADRを守るテスト / 実装ポインタ（Phase 2 以降で実装）

- `discord/backend/cmd/server/main.go` — Gateway プロセス entrypoint (HTTP + WS を 1 プロセス)
- `discord/backend/internal/gateway/hub.go` — per-guild Hub goroutine
- `discord/backend/internal/gateway/registry.go` — HubRegistry (`map[guildID]*Hub`)
- `discord/backend/internal/gateway/client.go` — ws client connection + IDENTIFY 処理
- `discord/backend/internal/gateway/hub_test.go` — Hub の register/unregister/broadcast の不変条件
- `discord/playwright/tests/fanout.spec.ts` — 2 BrowserContext で「同じ guild の別タブに message が届く」E2E

## 関連 ADR

- ADR 0002: Hub の goroutine + channel 実装パターン (本 ADR の Hub の中身)
- ADR 0003: プレゼンスのハートビート設計 (Hub が clients を生死判定する仕組み)
- ADR 0004: 認証 (WebSocket での JWT 受け渡し)
- ADR 0005 (派生予定): multi-process shard + Redis pub/sub
- ADR 0006 (派生予定): メッセージ broadcast の at-least-once 保証 (transactional outbox)
- ADR 0007 (派生予定): 再接続時の差分配信 (op `RESUME`)
- 関連: `slack/docs/adr/0001-realtime-actioncable.md` — Rails 側の同問題への解
