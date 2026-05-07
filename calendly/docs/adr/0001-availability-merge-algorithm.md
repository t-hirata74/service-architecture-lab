# ADR 0001: availability merge アルゴリズム — 都度計算 + index 駆動の SQL 集合演算

## ステータス

Accepted（2026-05-07）

## コンテキスト

calendly は **「host が公開した availability から、invitee が予約可能な時間スロットを取得する」** が中核機能。スロット取得は以下を merge して残った空き区間を返す:

- **availability_rules** (host が定義した受付時間。例: 平日 9:00-17:00、recurring を持つ → ADR 0003)
- **busy_periods** (host の既存予定 / Google Calendar 風の外部カレンダーから入る想定だが本リポではモック)
- **bookings** (既に確定した予約)
- **buffers** (会議前後の準備時間。`event_type.before_buffer_minutes`)
- **min_notice / max_advance_days** (「1 時間後以降しか予約不可 / 60 日先まで」のようなポリシー)

リクエストごとの計算量は通常 1 host × 1〜2 週間ぶんで、busy_periods + bookings の件数は数十オーダー。**ローカル完結 + 学習目的**という制約の下で、複雑なマテリアライズ層は持たないのが筋。

ただし MVP 後にスケールを意識した時の発展ポイント (キャッシュ層を入れる / busy_periods の前計算 / GraphQL persisted query) は ADR 派生候補として残す。

## 決定

**「リクエスト毎に SQL 集合演算で空き区間を計算する eager merge」** を採用する。

- 入力: `event_type_id`, `from`, `to`, `tz` (invitee 側の表示 TZ)
- 計算手順 (Rails service object):
  1. `availability_rules` を `from..to` 窓で **展開** (RRULE → busy/free intervals。ADR 0003)
  2. `busy_periods` + `bookings` (status: confirmed) を取得し、`[start, end)` の closed-open intervals を作る
  3. 1 と 2 の差集合を取り、`event_type.duration` でスライスして候補スロットを生成
  4. `before_buffer_minutes / after_buffer_minutes` で前後を縮める
  5. `min_notice` / `max_advance_days` で頭尾を切る
  6. invitee 側 `tz` で時刻を整形して返す (UTC → tz 変換 / DST 配慮 → ADR 0003)
- DB index は `bookings(event_type_id, start_at)`, `busy_periods(host_id, start_at)` の **複合 B-tree** でレンジクエリを高速化

### 「閉開区間」を採用する理由

`[start, end)` で統一する。`end_at` を **含めない** ことで「14:00-15:00 と 15:00-16:00 が連続して予約可能」(隣接区間が overlap 扱いにならない) が SQL 1 行で書ける:

```ruby
# 競合判定 (overlap)
booked.where("start_at < ? AND end_at > ?", new_end, new_start).exists?
```

両端閉だと `15:00 = 15:00` が overlap 扱いになり、`>=` か `>` の使い分けで毎度バグる。

## 検討した選択肢

### 1. 都度 eager merge ← 採用

- リクエストごとに上記 6 ステップを SQL + Ruby で実行
- 利点: シンプル / キャッシュ無効化のバグが起きない / DB index で十分速い (host あたり 数十 row)
- 利点: 「予約後の `slots` 取得が古いスロットを返す」事故が原理的に起きない
- 欠点: 大規模化時 (host が数千 host のスロットを並列取得する管理画面など) は素朴計算で詰まる

### 2. busy intervals を materialized cache に前計算

- `host_busy_intervals_cache(host_id, start_at, end_at)` を持ち、bookings/busy_periods 変更時に invalidate
- 利点: 大規模並列 read 時に O(1) lookup
- 欠点: cache invalidation が困難。booking 作成と cache 更新が atomic でないと「キャッシュが古いまま空きを返してダブルブッキング」を生む。本リポ MVP では複雑さに見合わない
- 欠点: 学習主旨 (制約充足アルゴリズム自体を学ぶ) から逸れる

### 3. PostgreSQL の `tstzrange` + GiST index で集合演算

- 区間型 + `&&` 演算子 + `range_agg` で SQL 1 文で merge できる
- 利点: 表現力が高い / 並列パフォーマンスも良い
- **却下理由: 本リポは MySQL 統一**。PostgreSQL に切り替えると他プロジェクトとの一貫性が崩れる (`slack` / `youtube` / `shopify` / `zoom` 全て MySQL 8)

### 4. 確定スロットを `available_slots` テーブルとして物理化

- 5 分刻みで予約可能 / 不可能 を静的に並べ、`booked = false` を SELECT
- 利点: read 1 query で済む
- 欠点: 行数爆発 (1 host × 60 日 × 96 スロット/日 = 5760 行) / RRULE 変更で全行再生成 / buffer の動的計算ができない

## 採用理由

- **学習価値**: 「**期間 overlap の SQL 表現**」「**閉開区間で統一する規律**」「busy/free intervals の集合演算」は他プロジェクトでは触れない領域。MySQL の制約 (range 型なし) の中でどう書くかが面白い
- **アーキテクチャ妥当性**: 実プロダクトの Cal.com も小規模時は都度計算 (cache は scale 後)。「最初は素直に書く」が定石
- **責務分離**: スロット計算は `Availability::SlotsService` (PORO) に閉じ、controller / model から独立。テストしやすい

## 却下理由

- 案 2 (cache): cache invalidation のバグが MVP に見合わない
- 案 3 (PG tstzrange): リポの DB 統一方針に反する
- 案 4 (静的物理化): 行数爆発 + RRULE 再生成コストが学習主旨を逸脱する

## 引き受けるトレードオフ

- **スループット限界**: host あたり数十〜数百 booking 規模では問題ない。10 万 booking 級には不向き → 派生 ADR で cache 層
- **計算結果の重複**: 連続したリクエストで同じ計算を毎回するが、同じ host / 同じ範囲なら HTTP cache (`Cache-Control: max-age=30`) で吸収可能 (本 ADR の対象外)
- **複雑なポリシー**: "1 日 3 件まで" のような per-host 制限は SQL 集計を 1 段増やす必要がある。ADR 0001 ではスコープ外、必要なら派生 ADR

## このADRを守るテスト / 実装ポインタ

(実装後に追記)

- `calendly/backend/app/services/availability/slots_service.rb` — 都度 merge の実装
- `calendly/backend/spec/services/availability/slots_service_spec.rb` — 各境界 (空き / 全埋まり / buffer / min_notice) を fixate
- `calendly/backend/spec/integration/booking_then_slots_spec.rb` — 予約直後にスロット取得して「同じ時間が候補から消える」不変条件

## 関連 ADR

- ADR 0002: 同時予約レース防止 — 「スロット取得が空きと言ったが、確定時に競合する」を吸収する
- ADR 0003: RRULE 展開と timezone 永続化 — availability_rules の展開ロジックを規定
- ADR 派生候補: スロット計算結果の cache 層 (HTTP cache / Redis / materialized) — 大規模化時に検討
