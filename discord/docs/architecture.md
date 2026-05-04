# Discord 風リアルタイムチャット (Go) アーキテクチャ

Discord のアーキテクチャを参考に、**「ギルド (server) / チャンネル / メッセージ + WebSocket gateway + プレゼンス」** をローカル環境で再現する学習プロジェクト。

中核となる技術課題は以下の 4 つ:

1. **ギルド単位シャーディング + 単一プロセス Hub** — per-guild Hub goroutine + HubRegistry。slack の Rails ActionCable + Redis pub/sub との対比 ([ADR 0001](adr/0001-guild-sharding-single-process-hub.md))
2. **Hub の goroutine + channel 実装パターン** — single goroutine + select で `clients` map を専有、mutex なし ([ADR 0002](adr/0002-hub-goroutine-channel-pattern.md))
3. **プレゼンスのハートビート** — app 層 op 1 HEARTBEAT + Hub 内 ticker 監視 + offline broadcast ([ADR 0003](adr/0003-presence-heartbeat.md))
4. **認証 (JWT bearer + WebSocket query)** — REST + WS で同じ JWT、WS は `?token=` で受ける ([ADR 0004](adr/0004-auth-jwt-bearer.md))

> 本プロジェクトは CLAUDE.md「言語別バックエンド方針」の **Go プロジェクト 1 本目**。slack (Rails ActionCable) と用途が近接するため、**「Go × per-guild Hub + goroutine/channel」** に焦点を絞り、**Slack との実装比較が学習素材**。

---

## システム構成

```mermaid
flowchart LR
  user([User Browser])
  user -->|HTTPS / fetch| front[Next.js 16<br/>:3055]
  user -.->|WebSocket<br/>ws://...?token=<jwt>| api
  front -->|REST<br/>Authorization: Bearer| api[Go gateway<br/>:3060]
  api <-->|REST<br/>POST /summarize<br/>POST /moderate| ai[FastAPI ai-worker<br/>:8050]
  api --- mysql[(MySQL 8<br/>:3312)]
  ai --- mysql

  subgraph "Go process (single)"
    api
    hub1[Hub guild=1]
    hub2[Hub guild=2]
    api -.->|register / broadcast| hub1
    api -.->|register / broadcast| hub2
  end
```

- 永続化は **MySQL のみ** (Redis 不採用、ADR 0001)
- frontend ↔ backend は **REST (固定形) + WebSocket (`/gateway`)**
- backend ↔ ai-worker は REST 同期コール (`/summarize`, `/moderate`)
- ai-worker ↔ MySQL は **読み専接続のみ** (perplexity / instagram と同方針)
- 書き込み (Guild / Channel / Message / Member / User) は **すべて Go 経由**

### WebSocket のデータフロー

```mermaid
sequenceDiagram
  autonumber
  participant FE as Frontend
  participant API as Go gateway
  participant H as Hub (guild=1)
  participant DB as MySQL

  FE->>API: GET /gateway?token=<jwt> (Upgrade)
  API->>API: JWT 検証 (失敗で 401)
  API-->>FE: 101 Switching Protocols
  API->>FE: op:10 HELLO {heartbeat_interval: 10000}
  FE->>API: op:2 IDENTIFY {token, guild_id: 1}
  API->>DB: SELECT membership WHERE user_id=? AND guild_id=?
  API->>H: register(client)
  H-->>FE: op:0 DISPATCH READY {user, guild, channels}
  H->>H: presences[user_id] = online
  H-->>FE: op:0 DISPATCH PRESENCE_UPDATE (broadcast)

  loop heartbeat
    FE->>API: op:1 HEARTBEAT
    API->>API: client.lastHeartbeatAt = now
    API-->>FE: op:11 HEARTBEAT_ACK
  end

  Note over FE,API: REST POST /channels/:id/messages の側で:
  FE->>API: POST /channels/1/messages {body}
  API->>DB: INSERT messages
  API->>H: broadcast(MessageCreated)
  H-->>FE: op:0 DISPATCH MESSAGE_CREATE (全 subscribers)

  alt heartbeat 失敗
    H->>H: now - lastHeartbeatAt > interval * 1.5
    H->>H: unregister + close(send)
    H-->>FE: PRESENCE_UPDATE (offline) を残りの subscribers に
  end
```

詳細:
- per-guild Hub の構造は [ADR 0001](adr/0001-guild-sharding-single-process-hub.md)
- goroutine + channel の select pattern は [ADR 0002](adr/0002-hub-goroutine-channel-pattern.md)
- HELLO / HEARTBEAT / HEARTBEAT_ACK の op codes は [ADR 0003](adr/0003-presence-heartbeat.md)

---

## ドメインモデル

```mermaid
erDiagram
  USER ||--o{ MEMBERSHIP : "joins guilds"
  GUILD ||--o{ MEMBERSHIP : "has members"
  GUILD ||--o{ CHANNEL : "has channels"
  CHANNEL ||--o{ MESSAGE : "contains"
  USER ||--o{ MESSAGE : "authors"
```

| テーブル | 役割 |
| --- | --- |
| `users` | username (UNIQUE), `password_hash` (bcrypt), `created_at` |
| `guilds` | name, owner_id, created_at |
| `memberships` | `(guild_id, user_id)` UNIQUE PK 相当 + `role` (`owner / admin / member`) + joined_at |
| `channels` | `guild_id` FK, `name`, `created_at`、(guild_id, created_at) index |
| `messages` | `channel_id` FK, `user_id` FK, `body TEXT`, `created_at`、`(channel_id, created_at)` index、`(channel_id, id DESC)` で cursor pagination |

> マイグレーションは Phase 2 (users / guilds / memberships) と Phase 2 後半 (channels / messages) に分けて作成する。

---

## Gateway protocol (op codes)

| op | 方向 | 名前 | データ |
| --- | --- | --- | --- |
| 0  | server → client | DISPATCH       | `{op:0, t: "MESSAGE_CREATE" / "PRESENCE_UPDATE" / "READY", d: {...}}` |
| 1  | client → server | HEARTBEAT      | `{op:1, d: <last_seq>}` |
| 2  | client → server | IDENTIFY       | `{op:2, d: {token, guild_id}}` |
| 10 | server → client | HELLO          | `{op:10, d: {heartbeat_interval: 10000}}` |
| 11 | server → client | HEARTBEAT_ACK  | `{op:11}` |

- 接続後すぐに HELLO を送る
- IDENTIFY 完了で READY を返す (user / guild / channels の初期 payload)
- DISPATCH の `t` で event 種別 (`MESSAGE_CREATE` / `PRESENCE_UPDATE` / 派生で `MESSAGE_DELETE` 等)

詳細形式と server 側のバッファリング規約は [ADR 0003](adr/0003-presence-heartbeat.md)。

---

## REST API 概観 (Go gateway ↔ Frontend)

| メソッド | パス | 用途 |
| --- | --- | --- |
| `POST` | `/auth/register` | username / password で登録、JWT 返却 |
| `POST` | `/auth/login` | username / password で login、JWT 返却 |
| `GET`  | `/me` | JWT から user 情報 |
| `GET`  | `/guilds` | 自分が所属するギルド一覧 |
| `POST` | `/guilds` | ギルド作成 (作成者は owner role で auto-join) |
| `POST` | `/guilds/:id/members` | 自分を guild に join (オープン参加 MVP、本物は招待制) |
| `GET`  | `/guilds/:id/channels` | guild のチャンネル一覧 |
| `POST` | `/guilds/:id/channels` | チャンネル作成 |
| `GET`  | `/channels/:id/messages` | メッセージ一覧 (cursor pagination) |
| `POST` | `/channels/:id/messages` | メッセージ投稿 + Hub.broadcast |
| `POST` | `/channels/:id/summarize` | ai-worker `/summarize` 経由口 |
| `GET`  | `/gateway?token=<jwt>` | WebSocket upgrade |
| `GET`  | `/health` | DB / ai-worker 疎通サマリ |

> **cursor pagination**: `?before=<message_id>` で `id < before` を `(channel_id, id DESC)` index で取得。perplexity / instagram と同方針。

---

## ai-worker の責務 (Python / FastAPI)

| エンドポイント | 用途 | 入出力 |
| --- | --- | --- |
| `POST /summarize` | チャンネルの直近メッセージ要約 (mock) | `{messages: [{user, body}, ...]}` → `{summary}` |
| `POST /moderate` | メッセージのスパム / NSFW スコア (mock) | `{body}` → `{flagged, score, reasons: []}` |
| `GET /health` | 疎通確認 | `{ok: true}` |

> mock 実装の規律: hash ベース determinist。LLM / 外部 API 不使用。Django/instagram と同パターン。

---

## レスポンス境界

- 認可は **`auth middleware` で JWT 検証 + `context` に user_id 注入**
- guild / channel access は handler 内で **membership SELECT** をかける (per-channel 権限 overwrite は派生 ADR、MVP は guild membership のみ)
- **WebSocket 失敗時の挙動**:
  - **(A) upgrade 前**: token 検証失敗 → **HTTP 401** (upgrade させない)
  - **(B) IDENTIFY 失敗**: invalid token / not member → `op:0 DISPATCH t:"INVALID_SESSION"` 後 close
  - **(C) heartbeat 失敗**: `unregister + close(send)` → 残り subscribers に `PRESENCE_UPDATE (offline)` broadcast
- **REST 失敗時**: 通常の HTTP status (4xx / 5xx)
- **ai-worker 不通時**: `/summarize` `/moderate` は **空レスポンス + `degraded: true` で 200** (graceful degradation、[operating-patterns.md §2](../../docs/operating-patterns.md))

---

## 起動順序

```bash
# 1. インフラ
docker compose up -d mysql        # 3312

# 2. backend (Go)
cd backend
go mod download
go run ./cmd/server/migrate
go run ./cmd/server                # http://localhost:3060

# 3. ai-worker (別タブ)
cd ../ai-worker && python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
uvicorn main:app --port 8050

# 4. frontend (別タブ)
cd ../frontend && npm install
npm run dev                        # http://localhost:3055

# 5. E2E (Phase 5 で追加)
cd ../playwright && npm test
```

## ポート割り当て

| サービス | ポート | 備考 |
| --- | --- | --- |
| frontend (Next.js)  | 3055 | instagram の 3045 から +10 |
| backend (Go)        | 3060 | instagram の 3050 から +10 |
| ai-worker (FastAPI) | 8050 | instagram の 8040 から +10 |
| MySQL               | 3312 | instagram の 3311 から +1 |
| Redis               | (不使用) | 単一プロセス Hub なので broker 不要 (ADR 0001) |

## Phase ロードマップ

| Phase | 範囲 | 状態 |
| --- | --- | --- |
| 1 | scaffolding + ADR 4 本 + architecture.md + docker-compose | 🟢 設計フェーズ完了 |
| 2 | Go gateway（chi + `store`/SQL + JWT + bcrypt）+ Guild / Channel / Message / Member + REST CRUD + 認証 1 経路 | 🟢 完了 |
| 3 | WebSocket gateway (gorilla/websocket) + per-guild Hub + IDENTIFY/HEARTBEAT/DISPATCH op codes + presence broadcast | 🟢 完了 |
| 4 | ai-worker (FastAPI) `/summarize` `/moderate` + frontend (Next.js channels list / message feed / native WebSocket subscribe) | 🟢 完了 |
| 5 | Playwright (2 BrowserContext で fan-out 検証) + Terraform 設計図 + GitHub Actions CI workflows | ⚪ 未着手 |
