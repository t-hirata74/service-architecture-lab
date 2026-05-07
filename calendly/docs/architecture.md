# calendly アーキテクチャ

> 🔴 Phase 1 (設計フェーズ) — ADR 0001-0003 確定後の見取り図。実装は Phase 2 以降で更新する。

## ドメイン境界

| コンポーネント | 責務 | 主要オブジェクト |
| --- | --- | --- |
| **Rails backend** (`backend/`, Ruby 4) | 認証 / 予約 CRUD / 状態遷移 / availability 計算 / RRULE 展開 | `Host`, `EventType`, `AvailabilityRule`, `BusyPeriod`, `Booking`, `Availability::SlotsService`, `Bookings::CreateService` |
| **Next.js frontend** (`frontend/`) | host 管理画面 (event_type / availability 設定) / invitee 公開予約ページ / DST 跨ぎ表示 | App Router page, `useTimezone()` hook |
| **FastAPI ai-worker** (`ai-worker/`) | 候補スロットの **deterministic mock 推薦** (ADR スコープ外、optional) | `/recommend_slots` (sha256 シードで決定的) |
| **MySQL 8** | 永続化 (Solid Queue / Solid Cache 同居) | — |

## データモデル

ER の主要部 (ADR から導かれる必須カラムのみ)。

```text
hosts (id, email, name, default_tz_id, ...)
event_types (id, host_id, slug, duration_minutes, before_buffer, after_buffer,
             min_notice_minutes, max_advance_days, ...)
availability_rules (id, host_id, event_type_id, rrule, start_time_of_day,
                    end_time_of_day, tz_id, effective_from, effective_until)  -- ADR 0003
busy_periods (id, host_id, start_at, end_at)                                  -- UTC 保存
bookings (id, event_type_id, host_id, invitee_email, invitee_tz_id,
          start_at, end_at, status, created_at, ...)                          -- UTC 保存
  ├ index: (host_id, start_at, end_at, status)                                -- ADR 0002 overlap 検索用
  ├ check: start_at < end_at                                                  -- ADR 0001 closed-open
  └ enum status: pending / confirmed / cancelled / completed
```

ADR 別に効く制約:

- **ADR 0001**: `bookings(host_id, start_at)` index で overlap 検索を高速化、`[start, end)` 閉開区間で統一
- **ADR 0002**: overlap 検査 + `host` 行 `FOR UPDATE` で同時予約を直列化
- **ADR 0003**: 壁時計 + `tz_id` 保存 (availability_rules) / UTC 保存 (bookings, busy_periods)

## 主要フロー

### 1. 予約スロット取得 (read path)

```text
client → GET /event_types/:id/slots?from=2026-05-10&to=2026-05-17&tz=Asia/Tokyo
       → Availability::SlotsService.call
           ├ availability_rules を [from, to) で展開 (ADR 0003)
           ├ busy_periods + bookings(confirmed|pending) を取得
           ├ 集合差 + duration / buffer / min_notice でスライス (ADR 0001)
           └ invitee_tz で整形して JSON
```

### 2. 予約作成 (write path)

```text
client → POST /bookings { event_type_id, start_at, invitee_email, invitee_tz_id }
       → Bookings::CreateService.call
           ├ Host.lock("FOR UPDATE")                        -- ADR 0002
           ├ overlap 検査 (start_at < new_end AND end_at > new_start)
           │   └ confirmed | pending のみ対象
           ├ Booking.create!(status: confirmed)              -- 確定
           └ commit → 通知ジョブ (mock)
```

### 3. recurring availability の登録

```text
host → POST /availability_rules { rrule, start_time, end_time, tz_id }
     → AvailabilityRule.create! (RRULE 文字列はそのまま保存、展開しない)
```

### 4. 予約キャンセル

```text
invitee → DELETE /bookings/:id
        → Booking.cancel! (status: confirmed → cancelled)
        → 同 host の overlap 検査では cancelled は無視されるので、即時に同枠を別人が予約可能
```

## 失敗時の挙動

| 失敗 | 挙動 | 対応 |
| --- | --- | --- |
| 同時予約レースで 2 件目以降が衝突 | `BookingConflict` raise → controller で 409 | UI で「直前に他の方に予約されました」表示 (ADR 0002) |
| availability_rules の RRULE 文字列が壊れている | パース時に `RruleParseError` raise | host 設定画面で validation エラー表示 |
| DST スキップ時刻 (`02:30` が存在しない日) を含む登録 | tzinfo のデフォルト挙動に委ね、spec で fixate | ADR 0003 の派生 ADR 候補 |
| invitee が `tz_id="Mars/Olympus"` のような不正値 | `InvalidTimezone` raise → 400 | controller で IANA tz id を validate |
| Solid Queue ジョブ (通知 mock) が失敗 | `failed_executions` に残し手動再 enqueue | zoom と同流儀 |

## ローカル運用

```sh
# 1. MySQL を起動
docker compose up -d mysql                # mysql:3326

# 2. backend (Rails 8 / Ruby 4)
cd backend && bundle exec rails db:create db:migrate
bundle exec rails s -p 3100

# 3. ai-worker (FastAPI / optional)
cd ai-worker && python -m venv .venv && .venv/bin/pip install -r requirements.txt
.venv/bin/uvicorn app.main:app --port 8090

# 4. frontend (Next.js)
cd frontend && npm install && npm run dev   # :3105

# 5. (Phase 5) Playwright E2E
cd playwright && npm install && npm test
```

ポート割り当て:

| 役割 | host port | container port |
| --- | --- | --- |
| MySQL 8 | 3326 | 3306 |
| Rails backend | 3100 | 3000 |
| Next.js frontend | 3105 | 3000 |
| FastAPI ai-worker | 8090 | 8000 |

---

## ADR 索引

- [ADR 0001 — availability merge アルゴリズム](adr/0001-availability-merge-algorithm.md)
- [ADR 0002 — 同時予約レース防止 (MySQL における EXCLUDE 代替)](adr/0002-booking-race-mysql-exclude-alternative.md)
- [ADR 0003 — RRULE 展開と timezone 永続化](adr/0003-rrule-expansion-and-timezone.md)

## 関連する他プロジェクトの ADR

- shopify ADR 0003 (条件付き UPDATE で原子減算) — calendly ADR 0002 と同流派
- zoom ADR 0001 (会議ライフサイクル state machine) — `with_lock` で状態遷移を直列化と同流派
- github ADR 0002 (権限グラフの 2 層) — Resolver + Pundit の踏襲先

---

## Phase 別予定

| Phase | 内容 |
| --- | --- |
| **Phase 1** (現在) | scaffolding + ADR 0001-0003 + architecture.md (本ドキュメント) |
| Phase 2 | `rails new --api -d mysql` + 主要 migration + `ApplicationJob` / Solid Queue |
| Phase 3 | Models + `Bookings::CreateService` + `Availability::SlotsService` + `RruleExpansion` + spec (含 100 並行 thread) |
| Phase 4-3 | rodauth-rails JWT (perplexity / shopify / zoom と同形) |
| Phase 4-1 | Controllers + routes (REST) |
| Phase 4-2 | ai-worker (FastAPI) `/recommend_slots` deterministic mock |
| Phase 5-1 | CI ジョブ追加 (`zoom-` の前例を流用) |
| Phase 5-2 | frontend (Next.js 16) — host 設定画面 + invitee 公開予約ページ |
| Phase 5-3 | Playwright E2E (slots → book → conflict 1 シナリオ + DST 跨ぎ表示 1 シナリオ) |
| Phase 5-4 | Terraform 設計図 (本番想定 / apply はしない) |
