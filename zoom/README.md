# Zoom 風オンライン会議プラットフォーム (Rails 8 + Next.js 16 + FastAPI)

[Zoom](https://zoom.us/) を参考に、**「会議ライフサイクル状態機械 + ホスト/参加権限 + 録画→要約パイプライン」** をローカル環境で再現するプロジェクト。

WebRTC SFU は本リポのスコープ外（policy で「WebRTC は別領域」として除外）のため、メディア配信そのものはモック扱いとし、**会議の状態管理 / 権限 / 非同期パイプライン** に学習を集中させる。外部 SaaS / LLM は使用せず、ai-worker 側で deterministic な mock を実装することでローカル完結を保つ（リポ全体方針: [`../CLAUDE.md`](../CLAUDE.md)）。

---

## 見どころハイライト

> 🟢 **MVP 完成**: Phase 1-5 完了 (RSpec 67 件 + pytest 7 件 + Playwright 2 件 + Terraform validate / CI 4 ジョブ)

- **会議ライフサイクル state machine** (ADR 0001) — `STATUSES` ENUM × `TRANSITIONS` マップ × `with_lock` + `reload` + 早期 return で **at-least-once ジョブが冪等 no-op に落ちる**。失敗状態 (`recording_failed` / `summarize_failed`) は戻り遷移を持ち、リトライで吸収する設計
- **動的ホスト譲渡** (ADR 0002) — `meetings.host_id` (現在値) + `meeting_co_hosts` (中間テーブル) + `host_transfers` (append-only 監査) の 3 層。`host_transfers` は `readonly?` + `before_destroy` で **アプリ層から UPDATE / DELETE を物理的に拒否**、`updated_at` カラムを持たないことで append-only を schema レベルで signal
- **at-least-once 録画 → 要約パイプライン** (ADR 0003) — `summaries.meeting_id UNIQUE` で **結果テーブル側に冪等を寄せ**、idempotency_key を持たない (shopify webhook の §20 とは対称形)。`enqueue_after_transaction_commit = true` を `ApplicationJob` 側に書き、状態遷移と enqueue を同一 transaction に乗せる
- **deterministic ai-worker mock** — `transcript_seed = "meeting=#{id};duration=#{duration};title=#{title}"` を SHA256 → 固定 bullets array から選択することで、外部 LLM SDK 不使用方針を守りつつ「同じ会議には同じ要約」を保証 (E2E test の決定性も確保)
- **権限 2 層** — `MeetingPermissionResolver` (PORO) が `host?` / `co_host?` / `live_participant?` / `can_transfer_host?` を判定、`MeetingPolicy` (Pundit) は薄いラッパー。github の `PermissionResolver` 構造を継承、こちらは **動的譲渡** が新規論点
- **rodauth-rails JWT bearer** — perplexity / shopify と同形。`Authorization` レスポンスヘッダから素の JWT を取り出して frontend `localStorage` に保持
- **Playwright E2E** — Solid Queue を `SOLID_QUEUE_IN_PUMA=1` で Puma に同居させ、`ended → recorded → summarized` のジョブチェインを 1 プロセスで pickup。frontend は **production build (`next start`)** で起動して hydration race を回避

---

## アーキテクチャ概要

```mermaid
flowchart LR
  user([Browser])
  fe[Next.js 16<br/>:3095]
  api[Rails 8 API<br/>:3090]
  db[(MySQL 8<br/>:3316)]
  queue[Solid Queue<br/>同居]
  ai[FastAPI ai-worker<br/>:8080]

  user --> fe --> api
  api <--> db
  api -->|enqueue 録画 finalize / 要約| queue
  queue -->|HTTP 内部 ingress| ai
  ai -->|要約結果 POST| api
```

> 凡例: 実線 = HTTP、二重線 = DB 接続。WebRTC のメディアパスは存在しない（SFU はモック）。

---

## 計画している ADR (最低 3 本)

policy の「ADR 最低3本」要件に対し、以下 3 本を予定。詳細は `docs/adr/` 配下に追加予定。

- **ADR 0001: 会議ライフサイクルを state machine + 状態列で表現する**
  - `scheduled / waiting_room / live / ended / recorded / summarized` の状態遷移を Rails 側で `aasm` あるいは生 case 文 + `with_lock` で管理する選択。youtube ADR との対比（あちらはアップロードジョブ単位、こちらは会議という長寿命リソース単位）。
- **ADR 0002: ホスト / 共同ホスト / 参加者の権限モデル**
  - リソース所有者 (host) + 動的に付与可能な共同ホスト (co-host) + ウェイティングルーム入室許可。github の `PermissionResolver` 2 層構造との比較で、**動的権限付与（譲渡 / 委任）が中心** という違いを ADR に残す。
- **ADR 0003: 会議終了 → 録画 finalize → ai-worker 要約 の at-least-once パイプライン**
  - shopify の webhook ADR と同形（Solid Queue + idempotency key）だが、**外向きではなく内部 ingress 越しに ai-worker を呼ぶ** 点と **会議 1 件あたり 1 サマリ** の冪等保証が論点。

---

## ローカル起動

```sh
docker compose up -d mysql              # mysql:3316
cd backend && bundle exec rails db:create db:migrate
SOLID_QUEUE_IN_PUMA=1 INTERNAL_INGRESS_TOKEN=dev-internal-token \
  AI_WORKER_URL=http://127.0.0.1:8080 bundle exec rails s -p 3090

cd ../ai-worker && python -m venv .venv && .venv/bin/pip install -r requirements.txt
INTERNAL_TOKEN=dev-internal-token .venv/bin/uvicorn app.main:app --port 8080

cd ../frontend && npm install && npm run build && npm run start    # :3095

cd ../playwright && npm install && npx playwright install chromium
npm test                                                            # E2E 2 件
```

ポート割り当て:

| 役割 | host port | container port |
| --- | --- | --- |
| MySQL 8 | 3316 | 3306 |
| Rails backend | 3090 | 3000 |
| Next.js frontend | 3095 | 3000 |
| FastAPI ai-worker | 8080 | 8000 |

---

## 既存サービスとの関係

| 観点 | 比較対象 | zoom が学ぶこと |
| --- | --- | --- |
| 状態機械 | youtube (動画変換 state machine) | 「ジョブ寿命」ではなく「会議という長寿命エンティティ」の状態遷移 |
| 権限グラフ | github (Org/Team/Collaborator 継承) | **動的権限付与（共同ホスト譲渡）** が加わる |
| 非同期パイプライン | shopify (Solid Queue webhook 配信) | 内部 ingress (ai-worker) 向けの at-least-once + 1サマリ冪等 |
| WebSocket fan-out | slack / discord | **本プロジェクトでは扱わない**（参加者通知は polling か Server-Sent Events のいずれか、ADR で確定） |
