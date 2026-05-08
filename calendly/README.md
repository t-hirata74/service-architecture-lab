# Calendly 風日程調整プラットフォーム (Rails 8 + Ruby 4 + Next.js 16 + FastAPI)

[Calendly](https://calendly.com/) / [Cal.com](https://cal.com/) を参考に、**「期間 overlap + 同時予約レース防止 + RRULE 展開 / timezone 永続化」** をローカル環境で再現するプロジェクト。

WebRTC や決済はスコープ外。**「時刻ドメイン + 制約充足」** に学習を集中させる。外部 SaaS / LLM は使用せず、ai-worker 側で deterministic な mock を実装することでローカル完結を保つ（リポ全体方針: [`../CLAUDE.md`](../CLAUDE.md)）。

**本リポで初の Ruby 4 系プロジェクト** (policy [`Ruby バージョン方針`](../docs/service-architecture-lab-policy.md#ruby-バージョン方針))。Namespace / YJIT 強化 / 主要 gem (rodauth-rails / solid_queue / pundit) の Ruby 4 互換性をここで実地検証する。

---

## 見どころハイライト

> 🟢 **MVP 完成**: Phase 1-5 完了 (Rails 88 RSpec + pytest 7 + Playwright 2 件通過 / Terraform validate / CI 5 ジョブ)。**本リポ初の Ruby 4.0.3** で動作。

- **本リポ初の Ruby 4 採用** (policy [`Ruby バージョン方針`](../docs/service-architecture-lab-policy.md#ruby-バージョン方針)) — Rails 8.1.3 + rodauth-rails / solid_queue / pundit / graphql-ruby 周辺の互換性を実地検証 (gem 互換性 OK、特殊な hack なし)
- **availability merge** (ADR 0001) — 都度 SQL 集合演算 + **閉開区間 [start, end) 統一**で隣接予約 overlap を回避。tstzrange を使えない MySQL 制約下での代替実装が題材
- **同時予約レース防止** (ADR 0002) — PostgreSQL `EXCLUDE` 不在の MySQL で **host 行 `FOR UPDATE` + overlap 検査 + INSERT** を 1 transaction で。100 並行スレッド spec で「1 件成立 / 99 件 BookingConflict」を fixate (shopify ADR 0003 と同流派)
- **RRULE 展開と timezone 永続化** (ADR 0003) — **壁時計 + tz_id 保存 + lazy 展開**。米国 DST 春切替 (2026-03-08) を跨いでも壁時計 14:00 が維持されるテストで fixate
- **多層冪等** — `bookings(host_id, start_at, end_at, status)` 複合 index + `start_at < end_at` CHECK + `cancelled` 無視 scope で、衝突は HTTP 409 + アプリ層は `BookingConflict` rescue
- **enqueue_after_transaction_commit + ApplicationJob 規律** (zoom と同形 / `operating-patterns.md §21`) — 状態遷移 commit 後にジョブが pickup される orphan 防止
- **`:test` adapter 切替** — test 環境のみ ActiveJob を `:test` に切替えて `calendly_test_queue` 依存を unit test から分離 (testing-strategy.md に記載)
- **Playwright** — Solid Queue 不要 + frontend は `next start` (production build) で hydration race を回避 (zoom と同形)
- **Terraform 設計図** — VPC + multi-AZ RDS MySQL + ECS Fargate (backend / frontend / ai-worker) + Service Discovery + Secrets Manager。`terraform validate` まで通る

---

## アーキテクチャ概要

```mermaid
flowchart LR
  user([Browser])
  fe[Next.js 16<br/>:3105]
  api[Rails 8 / Ruby 4<br/>:3100]
  db[(MySQL 8<br/>:3326)]
  ai[FastAPI ai-worker<br/>:8090]

  user --> fe --> api
  api <--> db
  api -.optional.-> ai
  ai -.suggestion JSON.-> api
```

> ai-worker の役割は「**スロット推薦の deterministic mock**」(候補時間帯のスコアリング) を想定。コアの予約ロジックは Rails 側に閉じる。

---

## 計画している ADR (最低 3 本)

policy の「ADR 最低3本」要件に対し、以下 3 本を予定。詳細は `docs/adr/` 配下に追加予定。

- **ADR 0001: availability merge アルゴリズム**
  - host の既存予定 (busy intervals) + 既存予約 + 営業時間ルール (working_hours) を merge して空きスロットを返す方式の選定
  - 候補: (a) eager merge をリクエスト毎に毎回計算 / (b) busy intervals を前計算キャッシュ / (c) free intervals を materialized view で持つ
  - `tstzrange` の集合演算が PostgreSQL の自然形だが、本リポ MySQL 統一なので **MySQL での代替実装** を ADR で決め切る (start_at / end_at の closed-open ペア + 区間和演算 SQL)
- **ADR 0002: 同時予約レース防止 — MySQL における `EXCLUDE` 排他制約代替**
  - PostgreSQL なら `EXCLUDE USING gist (room WITH =, during WITH &&)` で 1 行で書ける排他制約が、MySQL に存在しない
  - 候補: (a) アプリ層 `with_lock` + 重複検査 (zoom と同形) / (b) 条件付き UPDATE で `affected_rows == 0` を弾く (shopify 在庫減算と同形) / (c) `INSERT ... SELECT WHERE NOT EXISTS` を SERIALIZABLE で囲む
  - 100 並行スレッドの spec で fixate (shopify 流) して、最終的に「**唯一の予約だけが成立する**」不変条件を保証する
- **ADR 0003: RRULE 展開と timezone 永続化**
  - recurring availability (毎週月-金 9:00-17:00 等) を `RRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR;...` で保存
  - 展開戦略: eager (window 期間分すべて行に展開) / lazy (取得時に都度展開) のどちらか + キャッシュ層
  - timezone: **すべて UTC で保存 + 元 TZ id を別カラム保持** が定石。DST 跨ぎ (例: 2026 年米国春の DST 開始) の挙動を spec で fixate
  - 採用 gem: `ice_cube` or 自前 (Ruby 4 標準ライブラリの拡張で済むかも)

---

## ローカル起動

```sh
docker compose up -d mysql                   # mysql:3326

cd backend && bundle exec rails db:prepare   # primary / cache / queue / cable
INTERNAL_INGRESS_TOKEN=dev-internal-token AI_WORKER_URL=http://127.0.0.1:8090 \
  bundle exec rails s -p 3100

cd ../ai-worker && python -m venv .venv && .venv/bin/pip install -r requirements.txt
.venv/bin/uvicorn app.main:app --port 8090

cd ../frontend && npm install && npm run build && npm run start    # :3105

cd ../playwright && npm install && npx playwright install chromium
npm test                                                            # E2E 2 件
```

ポート割り当て:

| 役割 | host port | container port |
| --- | --- | --- |
| MySQL 8 | 3326 | 3306 |
| Rails backend | 3100 | 3000 |
| Next.js frontend | 3105 | 3000 |
| FastAPI ai-worker | 8090 | 8000 |

---

## 既存サービスとの関係

| 観点 | 比較対象 | calendly が学ぶこと |
| --- | --- | --- |
| 期間制約 | shopify (在庫の compare-and-decrement) | shopify は「数量の減算」、calendly は「**期間の重複禁止**」。条件付き UPDATE の対称形 |
| 状態機械 | zoom (会議ライフサイクル) | zoom は「会議そのものの寿命」、calendly は「**会議の前段 = 予約**」。時間軸で隣接、技術論点は別 |
| 監査 | zoom (HostTransfer append-only) | 予約変更 / キャンセル履歴を append-only で残す可能性 (ADR 派生候補) |
| 認可 | github (PermissionResolver + Pundit 2 層) | host / invitee / 第三者観覧の権限。同形の 2 層を踏襲 |
| 言語/Ruby | (本リポ初の Ruby 4 採用) | Namespace の使いどころ + 既存 gem 互換性検証。policy 「Ruby バージョン方針」の発火条件評価材料を作る |
