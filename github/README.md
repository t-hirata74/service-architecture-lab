# GitHub風 Issue Tracker

GitHub のアーキテクチャを参考に、**権限グラフ** と **Issue / PR / Review の関係グラフ** と **CI ステータス集約** をローカル環境で再現する学習プロジェクト。

---

## このプロジェクトが扱う技術課題

機能網羅ではなく、以下の技術課題の再現を主目的とする。

- **権限グラフ**: Org / Team / Repository / Collaborator の継承解決を `PermissionResolver` 1 箇所に集約 (ADR 0002)
- **Issue / PR の関係グラフ**: 番号空間共有 + 別テーブル + Comment / Review / Label の polymorphic 関係 (ADR 0003)
- **GraphQL field 単位認可**: REST と異なる API スタイルの選定理由とトレードオフ (ADR 0001)
- **CI ステータス集約**: 個別チェックの永続化と PR 単位の集約値の派生 (ADR 0004)
- **Rails ↔ Python ai-worker の境界**: AI レビュー / コード要約 / モック CI チェックランナー

採用した設計判断は `docs/adr/` を参照。

---

## 採用したスコープ

| 含める | 除外 |
| --- | --- |
| Org / Team / Repository / Collaborator の権限階層 | SSO / SAML / 2FA |
| Issue (open/closed) + Comment + Label + Assignee | Issue templates / projects / milestones の作り込み |
| PR + Review + RequestedReviewer + mergeable_state | 実 git 操作 / diff レンダリング / inline review |
| CI チェック upsert + 集約状態 | Actions ランナー / artifact ストレージ |
| AI レビュー（モック） / Issue 要約（モック） | Marketplace / 課金 / Webhook 配信保証 |

---

## アーキテクチャ概要

詳細な構成図・ドメインモデル・GraphQL スキーマ概観は **[docs/architecture.md](docs/architecture.md)** を参照。

主要要素：

- **Frontend (Next.js 16 / React 19)** — App Router + urql + graphql-codegen
- **Backend (Rails 8 API mode)** — graphql-ruby + graphql-batch + Pundit
- **ai-worker (FastAPI / Python 3.13)** — AI レビュー / 要約 / モック CI チェックランナー
- **MySQL 8** — 永続化 + Solid Queue/Cache を専用 DB で分離

> Slack / YouTube との違い: **API スタイルが GraphQL**（[../docs/api-style.md](../docs/api-style.md) で選定理由を整理）。

---

## ローカル起動（Phase 2 以降で動作）

### 前提

- Docker / Docker Compose
- Node.js 20+ (frontend 開発時)
- Ruby 3.3+ (backend 開発時)
- Python 3.12+ (ai-worker 開発時)

### 起動

```bash
# 1. インフラ
docker compose up -d mysql              # 3309

# 2. backend (Phase 2 以降)
cd backend && bundle install
bundle exec rails db:prepare
bundle exec rails server -p 3030

# 3. ai-worker (Phase 5 以降)
cd ../ai-worker
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
uvicorn main:app --port 8020

# 4. frontend (Phase 2 以降)
cd ../frontend && npm install
npm run dev                              # http://localhost:3025
```

---

## ステータス

| コンポーネント | ステータス |
| --- | --- |
| ADR (0001-0004)            | 🟢 Phase 1 完了 (Accepted) |
| アーキテクチャ図           | 🟢 docs/architecture.md |
| ディレクトリ scaffolding   | 🟢 backend / frontend / ai-worker / infra placeholder |
| docker-compose             | 🟢 MySQL のみ (3309) |
| Backend (Rails 8 + GraphQL) | 🟢 Phase 5a 完了: commit_checks + 集約 (PullRequest.checkStatus) + Internal ingress / RSpec 63 件 |
| Frontend (Next.js + urql)   | 🟢 Phase 5b 完了: organization / repository / PR 詳細 + checkStatus バッジ / lint / typecheck / build 通過 |
| ai-worker (Python)          | 🟢 Phase 5a 完了: /review / /code-summary / /check/run 実装 + backend ingress 疎通 |
| Solid Queue                 | ⚪ Phase 5b 未着手 |
| E2E (Playwright)            | ⚪ Phase 5b 未着手 |
| インフラ設計図 (Terraform)  | ⚪ Phase 5b 未着手 |
| CI (GitHub Actions)         | ⚪ Phase 5b 未着手 |

---

## ドキュメント

- [アーキテクチャ図](docs/architecture.md) — システム構成 / ドメインモデル / GraphQL 概観
- [ADR 一覧](docs/adr/) — 設計判断の記録（4 件 Accepted）
  - [0001 GraphQL 採用](docs/adr/0001-graphql-adoption.md)
  - [0002 権限グラフ](docs/adr/0002-permission-graph.md)
  - [0003 Issue / PR データモデル](docs/adr/0003-issue-pr-data-model.md)
  - [0004 CI ステータス集約](docs/adr/0004-ci-status-aggregation.md)
- リポジトリ全体の方針: [../CLAUDE.md](../CLAUDE.md)
- API スタイル選定: [../docs/api-style.md](../docs/api-style.md)

---

## Phase ロードマップ

| Phase | 範囲 | 成果物 |
| --- | --- | --- |
| 1 | 雛形 + ADR + architecture.md + docker-compose | 🟢 完了 |
| 2 | Org / Team / User / Repository + PermissionResolver + GraphQL `viewer` / `organization` / `repository` | 🟢 完了 (RSpec 18 件) |
| 3 | Issue / Comment / Label + IssueNumberAllocator + Mutation `createIssue` / `closeIssue` / `assignIssue` / `addComment` | 🟢 完了 (RSpec 34 件) |
| 4 | PullRequest / Review / RequestedReviewer + Mutation `createPullRequest` / `requestReview` / `submitReview` / `mergePullRequest` + Issue/PR 番号空間共有 | 🟢 完了 (RSpec 51 件) |
| 5a | CI 集約 (commit_checks + PullRequest.checkStatus) + ai-worker (/review, /code-summary, /check/run) + backend Internal ingress | 🟢 完了 (RSpec 63 件 / 全層疎通) |
| 5b | Frontend (Next.js 16 + urql + graphql-codegen) + viewer 切替 + repository / PR 詳細 + CI バッジ | 🟢 完了 (build / lint / typecheck 通過 / 3 ルート 200) |
| 5c | Playwright E2E + Terraform 設計図 + CI workflows + MVP 化 | ⚪ |
