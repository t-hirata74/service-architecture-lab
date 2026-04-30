# YouTube風 Video Platform

YouTube のアーキテクチャを参考に、**動画変換パイプラインの状態機械** と **レコメンドの責務分離** をローカル環境で再現する学習プロジェクト。

---

## このプロジェクトが扱う技術課題

機能網羅ではなく、以下の技術課題の再現を主目的とする。

- **アップロード状態機械**: `uploaded → transcoding → ready → published` の遷移と失敗時のハンドリング
- **非同期ワーカー**: DB-driven Queue (Solid Queue) でジョブ enqueue とビジネス更新をトランザクション整合
- **レコメンドの責務分離**: Rails ↔ Python ai-worker の境界（Slack の要約と同じパターンを別ドメインで再現）
- **動画ストレージ設計**: Active Storage local → 本番想定 S3 + CloudFront を Terraform で示す
- **検索の責務分離**: MySQL FULLTEXT (ngram) で MVP、必要なら別レイヤーへ

採用した設計判断は `docs/adr/` を参照。

---

## 採用したスコープ

| 含める | 除外 |
| --- | --- |
| 動画メタデータ管理 / アップロード状態機械 | 実コーデックでの動画変換 |
| コメント（ネスト1段まで） | ライブ配信 / WebRTC |
| 検索（FULLTEXT 最小） | 収益化 / 広告挿入 |
| 関連動画レコメンド（モック） | 視聴履歴ベースのパーソナライズ |
| サムネ生成（モック / Pillow） | エンコーダ設定の作り込み |

---

## アーキテクチャ概要

詳細な構成図・状態機械・レコメンド境界は **[docs/architecture.md](docs/architecture.md)** を参照。

主要要素：

- **Frontend (Next.js 16 / React 19)** — App Router で SSR / 動画一覧・詳細・アップロード UI
- **Backend (Rails 8 API mode)** — Solid Queue で状態機械、Active Storage で動画永続化
- **ai-worker (FastAPI / Python 3.13)** — レコメンド / タグ抽出 / サムネ生成のモック
- **MySQL 8** — 永続化 + Solid Queue/Cache/Cable の専用 DB を分離（ADR 0001 / ADR 0004）

> Slack 構成との違い: **Redis を使わない**。Solid トリオ (Queue/Cache/Cable) で DB に統一（ADR 0001）。

---

## ローカル起動

### 前提

- Docker / Docker Compose
- Node.js 20+ (frontend 開発時)
- Ruby 3.3+ (backend 開発時)
- Python 3.12+ (ai-worker 開発時)

### 起動

```bash
# 1. インフラ
docker compose up -d mysql              # 3308

# 2. backend
cd backend && bundle install
bundle exec rails db:prepare
bundle exec rails server -p 3020

# 2b. Solid Queue worker (Phase 3 アップロード遷移を進めるために必要)
bundle exec bin/jobs

# 3. ai-worker
cd ../ai-worker
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
uvicorn main:app --port 8010

# 4. frontend
cd ../frontend && npm install
npm run dev                              # http://localhost:3015
```

ブラウザで http://localhost:3015 を開くと動画一覧（SSR）が表示される。`/diagnostics` で backend の `/health` 疎通を確認できる。

---

## ステータス

| コンポーネント | ステータス |
| --- | --- |
| インフラ（MySQL）          | 🟢 起動・db:prepare 通過確認済み |
| Backend (Rails 8)          | 🟢 Phase 4: 状態機械 + Solid Queue + Active Storage + ai-worker 統合 / RSpec 40 件 |
| Frontend (Next.js)         | 🟢 Phase 4: 一覧 / 詳細 (サムネ + 関連動画) / アップロード / 状態ポーリング UI |
| Solid Queue worker         | 🟢 `bin/jobs` が Transcode → ExtractTags → GenerateThumbnail のチェインを駆動 |
| ai-worker (Python)         | 🟢 Phase 4: recommend / tags / thumbnail を Rails から呼び出し動作確認 |
| レコメンド境界             | 🟢 ADR 0003 Accepted (Jaccard モック / 失敗時 `degraded: true`) |
| E2E (Playwright)           | ⚪ Phase 5 で追加予定 |
| インフラ設計図 (Terraform) | ⚪ Phase 5 で追加予定 |
| ADR                        | 🟡 0001-0002 / 0004 Proposed / 0003 / 0005 Accepted |

---

## ドキュメント

- [アーキテクチャ図](docs/architecture.md) — システム構成・状態機械・レコメンド境界の Mermaid 図
- [ADR 一覧](docs/adr/) — 設計判断の記録（4 件 Proposed / 着手前提）
- リポジトリ全体の方針: [../CLAUDE.md](../CLAUDE.md)

---

## Phase ロードマップ

| Phase | 範囲 | 成果物 |
| --- | --- | --- |
| 1 | 雛形 + 各サービス疎通 | ✅ 完了 |
| 2 | 動画メタデータ CRUD + 一覧/詳細 UI | ✅ 完了 |
| 3 | アップロード + 状態機械 + Solid Queue | ✅ 完了 |
| 4 | ai-worker 統合（recommend / tags / thumbnail） | ✅ いまここ |
| 5 | コメント + 検索 + Playwright E2E + Terraform + CI | — |
