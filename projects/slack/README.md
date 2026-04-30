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

```txt
┌─────────────┐       ┌─────────────┐       ┌─────────────┐
│  Frontend   │◀─────▶│   Backend   │◀─────▶│  ai-worker  │
│ (Next.js)   │       │   (Rails)   │       │  (Python)   │
└─────────────┘       └─────────────┘       └─────────────┘
       ▲                     ▲                     ▲
       │                     │                     │
       │              ┌──────┴──────┐              │
       └──────────────│    Redis    │──────────────┘
                      │  (Pub/Sub)  │
                      └─────────────┘
                             ▲
                      ┌──────┴──────┐
                      │    MySQL    │
                      └─────────────┘
```

詳細図は `docs/architecture.md` 参照（追記予定）。

---

## ローカル起動

### 前提

- Docker / Docker Compose
- Node.js 20+ (frontend 開発時)
- Ruby 3.3+ (backend 開発時)
- Python 3.12+ (ai-worker 開発時)

### 起動

インフラ（MySQL / Redis）：

```bash
docker compose up -d mysql redis
```

> MySQL のホスト側ポートは **3307**（他プロジェクトとの 3306 競合回避）。

Backend（Rails）— ローカル実行：

```bash
cd backend
bundle install
bundle exec rails db:create db:migrate
bundle exec rails server   # http://localhost:3000
```

`frontend` / `ai-worker` は実装完了次第、compose に追加していく。

---

## ステータス

| コンポーネント | ステータス |
| --- | --- |
| インフラ（MySQL, Redis）   | 🟢 起動・migrate 通過確認済み |
| Backend (Rails)            | 🟡 Rails 8 + rodauth-rails 初期セットアップ済み |
| Frontend (Next.js)         | ⚪ 未着手 |
| ai-worker (Python)         | ⚪ 未着手 |
| ADR                        | 🟢 0001 / 0002 / 0003 / 0004 採択済み |

---

## ドキュメント

- [ADR 一覧](docs/adr/)
- リポジトリ全体の方針：[../../CLAUDE.md](../../CLAUDE.md)
