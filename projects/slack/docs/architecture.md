# Slack 風プロジェクト アーキテクチャ

このドキュメントは技術課題と実装の対応を Mermaid 図で示す。設計判断の根拠は ADR を参照（[docs/adr/](adr/)）。

---

## システム全体図

```mermaid
flowchart LR
    subgraph Browser
      FE[Next.js 16<br/>React 19<br/>Tailwind v4]
    end

    subgraph Backend["Rails 8 (API mode)"]
      RC[REST Controller<br/>/me /channels /messages /read /join /summary]
      AC[ActionCable<br/>MessagesChannel / UserChannel]
      RA[rodauth-rails<br/>JWT 認証]
    end

    AW[ai-worker<br/>FastAPI / Python 3.13]
    DB[(MySQL 8)]
    RD[(Redis 7<br/>Pub/Sub)]

    FE -- "JWT (Authorization)<br/>REST" --> RC
    FE -- "JWT (?token=)<br/>WebSocket" --> AC
    FE -- "/create-account /login" --> RA

    RC --> DB
    AC --> RD
    RC -- "broadcast" --> AC
    RC -- "POST /summarize" --> AW
```

**ADR 対応**:
- WebSocket + Redis Pub/Sub: [ADR 0001](adr/0001-realtime-delivery-method.md)
- メッセージ永続化と既読 cursor: [ADR 0002](adr/0002-message-persistence-and-read-tracking.md)
- DB に MySQL: [ADR 0003](adr/0003-database-choice.md)
- 認証: [ADR 0004](adr/0004-authentication-strategy.md)
- E2E に Playwright: [ADR 0005](adr/0005-browser-e2e-with-playwright.md)

---

## メッセージ配信フロー (ADR 0001)

```mermaid
sequenceDiagram
    autonumber
    participant Alice as Alice (Browser)
    participant Rails as Rails<br/>MessagesController
    participant DB as MySQL
    participant Redis as Redis Pub/Sub
    participant Bob as Bob (Browser)

    Note over Alice,Bob: 双方とも MessagesChannel(channel_id=X) を購読中

    Alice->>Rails: POST /channels/X/messages<br/>(Authorization: JWT)
    Rails->>DB: INSERT INTO messages
    DB-->>Rails: id=42
    Rails->>Redis: PUBLISH channel-X (id=42)
    Redis-->>Bob: WebSocket frame
    Redis-->>Alice: WebSocket frame
    Note over Alice,Bob: id で dedup<br/>(broadcast 経由のみで表示)
    Rails-->>Alice: 201 Created (JSON)
```

---

## 既読 cursor の単調増加と多デバイス同期 (ADR 0002)

```mermaid
sequenceDiagram
    autonumber
    participant TabA as Alice Tab A<br/>(チャンネル X 表示中)
    participant TabB as Alice Tab B<br/>(/channels で待機)
    participant Rails as Rails<br/>ChannelsController#read
    participant Mem as memberships<br/>(MySQL)
    participant Redis as Redis Pub/Sub

    Note over TabA: 最新メッセージ id=42 が画面表示
    TabA->>Rails: POST /channels/X/read<br/>{message_id: 42}
    Rails->>Mem: SELECT last_read_message_id
    Mem-->>Rails: 30 (現在値)
    Note over Rails: ADR 0002:<br/>42 > 30 なので advance
    Rails->>Mem: UPDATE last_read_message_id=42
    Rails->>Redis: PUBLISH user-Alice<br/>{type: read.advanced, channel_id: X, last_read: 42}
    Redis-->>TabA: WebSocket frame
    Redis-->>TabB: WebSocket frame
    Note over TabB: サイドバーの<br/>未読インジケータが消える
    Rails-->>TabA: 200 OK<br/>{advanced: true, last_read: 42}

    Note over TabA: 古い id=10 で再リクエスト (誤操作 / 競合)
    TabA->>Rails: POST /channels/X/read<br/>{message_id: 10}
    Rails->>Mem: SELECT last_read_message_id
    Mem-->>Rails: 42
    Note over Rails: 10 <= 42 なので<br/>UPDATE しない (単調増加ガード)
    Rails-->>TabA: 200 OK<br/>{advanced: false, last_read: 42}
```

---

## Rails ↔ ai-worker 境界

```mermaid
sequenceDiagram
    participant FE as Frontend
    participant Rails as ChannelsController#summary
    participant AW as ai-worker (FastAPI)

    FE->>Rails: GET /channels/X/summary<br/>(JWT 認証必須)
    Rails->>Rails: current_user.channels.find(X)<br/>(認可)
    Rails->>Rails: 直近 30 件メッセージ取得
    Rails->>AW: POST /summarize<br/>{channel_name, messages[]}
    Note over AW: 決定論的な mock 要約<br/>(LLM 呼び出しはせず)
    AW-->>Rails: 200 OK<br/>{summary, participants, message_count}
    Rails-->>FE: 200 OK (JSON)

    Note over Rails: 接続失敗時は AiWorkerClient::Error<br/>→ 502 Bad Gateway
```

---

## テスト戦略

| レイヤー | フレームワーク | カバレッジ |
| --- | --- | --- |
| 単体・統合 | Rails minitest | モデル / Channel / Connection / Broadcast (9 tests) |
| E2E | Playwright (chromium) | auth / fan-out / read-sync / summary (6 tests) |

---

## ポート構成（ローカル開発）

| サービス | ホストポート | 備考 |
| --- | --- | --- |
| frontend (Next.js) | 3005 | `.env.local` の NEXT_PUBLIC_API_URL = backend |
| backend (Rails) | 3010 | docker の 3000 と衝突回避のため移動 |
| ai-worker (FastAPI) | 8000 | uvicorn 直起動 |
| mysql | 3307 → 3306 | 他プロジェクト docker (yamanashi) と衝突回避 |
| redis | 6379 | デフォルト |

---

## 起動順序

```bash
# 1. インフラ
cd projects/slack
docker compose up -d mysql redis

# 2. backend (Rails)
cd backend
bundle exec rails db:create db:migrate
bundle exec rails server -p 3010

# 3. ai-worker (Python)
cd ../ai-worker
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
uvicorn main:app --port 8000

# 4. frontend (Next.js)
cd ../frontend
npm install
npm run dev   # http://localhost:3005

# 5. E2E (任意)
cd ../playwright
AI_WORKER_RUNNING=1 npm test
```
