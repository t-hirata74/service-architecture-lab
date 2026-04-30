# Slack風 Realtime Chat

Slack のアーキテクチャを参考に、リアルタイムチャットの**技術課題**をローカル環境で再現する学習プロジェクト。

---

## このプロジェクトが扱う技術課題

機能網羅ではなく、以下の技術課題の再現を主目的とする。

- **メッセージの fan-out**：1メッセージを多数の購読クライアントへ低遅延で配信する
- **既読カウンタの整合性**：複数デバイス間で既読状態をどう管理するか
- **リアルタイム購読の責務分離**：Frontend / Rails / Redis の役割をどう切るか
- **Rails ↔ ai-worker の境界設計**：要約・分析処理をどこで呼び、結果をどう返すか
- **検索の責務分離**：全文検索を Rails でやるか別レイヤーに切るか

採用した設計判断は `docs/adr/` を参照。

---

## 採用したスコープ

| 含める | 除外 |
| --- | --- |
| WebSocket によるリアルタイム配信 | ハドル（音声通話） |
| チャンネル / DM / メッセージ | 絵文字ピッカーの作り込み |
| 既読管理 | スレッド機能の作り込み（最小のみ） |
| 検索（最小） | エンタープライズ管理機能 |
| 通知（アプリ内のみ、1経路） | メール / プッシュ通知配信 |
| メッセージ要約（モック AI） | Slackbot / アプリ統合 |

---

## アーキテクチャ概要

詳細な構成図・配信シーケンス・既読同期シーケンスは **[docs/architecture.md](docs/architecture.md)** を参照。

主要要素：

- **Frontend (Next.js 16 / React 19)** — JWT を localStorage に保持、`@rails/actioncable` で WebSocket 購読
- **Backend (Rails 8 API mode)** — rodauth-rails で JWT 認証、ActionCable + Redis で fan-out
- **ai-worker (FastAPI / Python 3.13)** — メッセージ要約のモック実装
- **MySQL 8** — 永続化 (Slack 自身の構成と整合 / ADR 0003)
- **Redis 7** — Pub/Sub アダプタ (ADR 0001)

---

## ローカル起動

### 前提

- Docker / Docker Compose
- Node.js 20+ (frontend 開発時)
- Ruby 3.3+ (backend 開発時)
- Python 3.12+ (ai-worker 開発時)

### 起動

詳細は [docs/architecture.md](docs/architecture.md#起動順序) を参照。

```bash
# 1. インフラ
docker compose up -d mysql redis    # 3307, 6379

# 2. backend
cd backend && bundle exec rails db:create db:migrate
bundle exec rails server -p 3010

# 3. ai-worker
cd ../ai-worker && source .venv/bin/activate
uvicorn main:app --port 8000

# 4. frontend
cd ../frontend && npm run dev        # http://localhost:3005

# 5. E2E (任意)
cd ../playwright && AI_WORKER_RUNNING=1 npm test
```

---

## ステータス

| コンポーネント | ステータス |
| --- | --- |
| インフラ（MySQL, Redis）   | 🟢 起動・migrate 通過確認済み |
| Backend (Rails)            | 🟢 認証 / REST / ActionCable / ai-worker 連携 (minitest 9 件) |
| Frontend (Next.js)         | 🟢 Next 16 / Tailwind v4 / 認証 / チャット / 既読 / 要約 UI |
| ai-worker (Python)         | 🟢 FastAPI でメッセージ要約 mock |
| E2E (Playwright)           | 🟢 chromium で 6 ケース通過 (auth/fanout/read-sync/summary) |
| ADR                        | 🟢 0001〜0005 採択済み |

---

## ドキュメント

- [アーキテクチャ図](docs/architecture.md) — システム全体・配信フロー・既読同期・ai-worker 境界の Mermaid 図
- [ADR 一覧](docs/adr/) — 設計判断の記録 (5 件採択済み)
- リポジトリ全体の方針：[../../CLAUDE.md](../../CLAUDE.md)
