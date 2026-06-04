# ADR 0003: rollup テーブル（冪等 upsert）+ series registry + retention

## ステータス

Accepted（2026-06-04）

## コンテキスト

ADR 0001 の aggregator が固定窓で集約した結果を **どう MySQL に永続し、どうクエリ可能にするか**が本 ADR の論点。要件:

- **冪等な flush**: flush は at-least-once（DB 一時障害で再試行する、ADR 0001 の retention 内で再 upsert）。同じ（series, 窓, resolution）への二重書きが破壊的であってはならない。
- **クエリ**: ダッシュボードが `metric + tag matcher + 期間 + 集計` で時系列を引く。
- **cardinality 管理**: 既知 series を列挙し、active series 数を把握できる（ADR 0002 の上限判定にも使う）。
- **メモリ/ストレージ有界**: in-memory ring は直近 N 窓のみ。`rollups` も retention で削る。

制約: ローカル完結（MySQL 8 のみ、専用 TSDB なし）、生 SQL（discord/uber の `database/sql` 方針）。

## 決定

**downsampled `rollups` テーブル（`UNIQUE(series_key, bucket_ts, resolution_s)` で冪等 upsert）+ `series` registry + 単一 resolution の retention** を採用する。

- `rollups`: `series_key`, `bucket_ts`（窓開始 UTC）, `resolution_s`, `count`, `sum`, `min`, `max`, `last`, `hist`(JSON, histogram のみ)。**`UNIQUE(series_key, bucket_ts, resolution_s)`** + `INSERT ... ON DUPLICATE KEY UPDATE`（MySQL upsert）で flush 再実行を冪等吸収。
- `series`: `series_key`(UNIQUE), `metric_name`, `tags`(JSON), `type`, `first_seen`, `last_seen`。新規 series 初出時に登録（cardinality カウントの真実）。
- **query**: `metric_name` + tag matcher で `series` を絞り、その `series_key` 群の `rollups` を期間で引いて集計（sum/avg/max…）。`(series_key, bucket_ts)` index。
- **retention**: 定期ジョブ（aggregator の flush tick に同居）で `bucket_ts < now - retention` の `rollups` を DELETE。多段ダウンサンプリングは設計言及のみ。

## 検討した選択肢

### 1. rollup テーブル + 冪等 upsert + series registry ← 採用

- flush の at-least-once を `UNIQUE` + upsert で吸収（zoom の「結果テーブル UNIQUE で冪等」/ shopify ledger と同じ整合性パターンの観測版）。
- 集約済みなので行数が `series × 窓数` に有界。query が速い。
- series registry で cardinality を一元管理。

### 2. raw events テーブル（生サンプルを全保存）

- 後から任意 resolution で再集計できる柔軟性。
- 欠点: 行数が `サンプル数` で爆発、query が常に GROUP BY 集計で重い。ADR 0001 の in-memory 集計と二重投資。ローカルでは破綻。

### 3. 専用 TSDB（列指向圧縮 / Gorilla 等）

- 本物の観測基盤に最も近い。
- 欠点: ローカル完結・MySQL 統一方針から外れ、実装が学習主題（Go 並行性）から逸脱。列指向の思想は ADR で言及するに留める。

### 4. 完全 in-memory（永続なし）

- 最小。
- 欠点: 再起動で消失、query が直近窓限定。却下（ADR 0001 と同じ理由）。

## 採用理由

- **学習価値**: 「append-only log/raw」ではなく **「事前集約 rollup + 冪等 upsert」** という観測基盤の定石を実装。`UNIQUE` による at-least-once 冪等は本リポ横断パターン（zoom/shopify）の観測版。
- **アーキテクチャ妥当性**: Prometheus recording rules / Datadog の rollup と同じ downsampling 思想。
- **責務分離**: `series`（メタ/cardinality）と `rollups`（数値時系列）を分離。query は series で絞って rollups を読む 2 段。
- **将来の拡張性**: resolution を複数（10s / 1m / 1h）持たせ多段ダウンサンプリング、`hist` を sketch（DDSketch 等）に発展可能。

## 却下理由

- 案 2（raw events）: 行爆発 + query 重 + ADR 0001 と二重。
- 案 3（専用 TSDB）: ローカル完結逸脱、学習主題から外れる。
- 案 4（完全 in-memory）: 永続/query が痩せる。

## 引き受けるトレードオフ

- **生サンプルを捨てる**: rollup 後に元サンプルは残らない。事後の任意 resolution 再集計は不可（事前に決めた resolution のみ）。観測用途では許容。
- **histogram の近似**: `hist` を固定バケット JSON で持つため percentile は近似。正確 percentile は sketch（派生）。
- **単一 resolution**: MVP は 1 resolution。長期保存の多段化は未実装。
- **JSON tags の検索性**: tag matcher は JSON 列ベースで弱い。MVP の規模では許容、必要なら正規化 tag テーブル（派生）。

## このADRを守るテスト / 実装ポインタ

- `datadog/backend/internal/store/rollup_test.go`（予定）— 同一 `(series_key, bucket_ts, resolution_s)` への二重 flush が count/sum を二重計上しない（冪等 upsert）/ retention DELETE が境界で正しく効く。
- `datadog/backend/migrations/001_init.up.sql`（予定）— `rollups` の `UNIQUE` 制約 + index、`series` registry。

## 関連 ADR

- ADR 0001: aggregator が flush する先
- ADR 0002: series registry が cardinality 上限判定の真実
- ADR 0004: alert engine が rollups を周期評価
