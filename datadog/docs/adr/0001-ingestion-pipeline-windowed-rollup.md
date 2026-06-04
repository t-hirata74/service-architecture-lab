# ADR 0001: fan-in ingestion パイプライン + single-owner aggregator + 固定窓 rollup

## ステータス

Accepted（2026-06-04）

## コンテキスト

観測基盤の中核は「大量のメトリクスサンプルを受け取り、時間窓で集約して保存・クエリ可能にする」こと。本プロジェクトは **Go バックエンド 3 本目**で、discord（`1→N fan-out`）/ uber（`2 者マッチング`）が扱っていない **第3の Go 並行パターン = `多→1 fan-in パイプライン + backpressure`** を学習主題に置く。

制約:

- **ローカル完結**: 実 TSDB / マネージドサービスを使わず、Go + MySQL で完結。メトリクスは合成ジェネレータ。
- **高スループット ingestion**: 多数のサンプルを低レイテンシで受け、集計はメモリ常駐で行いたい。Ruby/Python は GIL で本物の並行集計が苦しい（Go を選ぶ理由、go.md §1）。
- **メモリ有界**: series × 時間窓を無制限に持てない。retention と cardinality 制御（ADR 0002/0003）が前提。
- 既存 Go 2 本との **対比学習**: 同じ single-goroutine ownership (CSP) で、専有する状態の形だけ変える。

## 決定

**`HTTP /ingest → bounded ingest chan → worker pool → single-owner aggregator goroutine` の fan-in パイプライン**で受け、**aggregator が `map[seriesKey]*series` と各 series の時間窓 ring buffer を専有**して固定窓（例 10s）に集約し、完了バケットを `rollups` テーブルに flush する。

- **handler**: line/JSON を decode → `Sample` を ingest chan に **non-blocking send**（満杯=drop、ADR 0002）。即 202。
- **worker pool (N goroutine)**: parse/validate + series key 計算（`name` + ソート済み tags のハッシュ）→ aggregator の sample chan へ。
- **aggregator (1 goroutine)**: `select { case <-samples: bucketize; case <-flushTicker.C: flushCompleted; case <-ctx.Done() }`。map と ring buffer は **この goroutine の専有**（mutex なし、race-free）。
- **flush**: 現在窓より過去の完了バケットを `rollups` に idempotent upsert（ADR 0003）。

## 検討した選択肢

### 1. fan-in パイプライン + single-owner aggregator + 固定窓 rollup ← 採用

- Go 標準の pipeline パターン（producer → bounded chan → worker pool → 集約）を正面から学べる。
- aggregator が状態を専有するので mutex 不要、テストで「サンプルを注入 → バケットを観測」が channel だけで駆動できる（discord Hub と同じ）。
- メモリは「直近窓のみ」で有界。flush で MySQL に逃がす。

### 2. raw event 保存 + query 時集計

- ingest が単純（行を INSERT するだけ）。
- 欠点: storage が無制限に増え、query が GROUP BY 時間窓で重い。in-memory 集計という **本 ADR の Go 学習主題が消える**。OLAP DB が前提になりローカル完結から外れる。

### 3. per-series goroutine（series ごとに 1 goroutine）

- series 単位で並行集計でき直感的。
- 欠点: 高基数（数万 series）で goroutine 爆発、flush の協調が複雑。single-owner + map のほうが制御とテストが簡単。シャーディングは将来 ADR。

### 4. 完全 in-memory（永続なし）

- 最小。
- 欠点: 再起動で全消失、query が直近窓に限定。学習範囲（永続 rollup / retention）が痩せる。

## 採用理由

- **学習価値**: Go の正準3並行パターン（fan-out / matching / **pipeline+fan-in**）の最後を埋める。bounded chan + worker pool + single-owner aggregator + flush という実務頻出構成を手で書ける。
- **アーキテクチャ妥当性**: Prometheus / StatsD / OpenTelemetry collector と同じ「push-time 集約 + downsampled 永続」。
- **責務分離**: 受信（handler）/ 整形・ルーティング（worker）/ 集約（aggregator）/ 永続（flush）が段で分かれる。
- **将来の拡張性**: aggregator を seriesKey でシャード化（`map[shard]*aggregator`）すれば水平に伸ばせる（discord per-guild Hub の発想を流用）。

## 却下理由

- 案 2（raw + query 時集計）: in-memory 集計の学びが消え、storage/query が重い。
- 案 3（per-series goroutine）: 高基数で goroutine 爆発、協調が複雑。
- 案 4（完全 in-memory）: 永続/retention/query の学習が痩せる。

## 引き受けるトレードオフ

- **最新窓の at-most-once**: プロセス再起動で未 flush の現在窓を失う（確定 rollup は永続）。観測用途では許容。
- **single aggregator のスループット上限**: 1 goroutine が全 series を捌くので、極端な高基数では飽和する。MVP 規模では十分、限界はシャーディング（派生 ADR）。
- **固定 resolution**: MVP は単一 resolution（例 10s）。多段ダウンサンプリングは設計言及のみ。

## このADRを守るテスト / 実装ポインタ

- `datadog/backend/internal/ingest/aggregator_test.go`（予定、`go test -race`）— サンプル注入 → 正しいバケットに count/sum/min/max が積まれる / 窓跨ぎで完了バケットが flush される。
- `datadog/backend/internal/ingest/pipeline.go`（予定）— handler / worker pool / aggregator の配線。
- 関連運用知は [operating-patterns.md](../../docs/operating-patterns.md) に昇華予定。

## 関連 ADR

- ADR 0002: backpressure + cardinality 制御（bounded chan の drop 方針）
- ADR 0003: rollup データモデル（flush 先の冪等 upsert）
- ADR 0004: alert engine（rollup を周期評価）
