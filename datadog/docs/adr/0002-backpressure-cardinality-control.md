# ADR 0002: backpressure (non-blocking drop / load shedding) + cardinality 制御

## ステータス

Accepted（2026-06-04）

## コンテキスト

ADR 0001 のパイプラインは bounded channel で繋がっている。**受信レートが処理能力を超えたとき**と、**series 数（cardinality）が爆発したとき**にどう振る舞うかが本 ADR の論点。観測基盤特有の事情:

- メトリクス送信は本質的に **fire-and-forget**。送信側は再送・順序を期待しない。
- 高基数（high-cardinality）は観測基盤最大の運用課題。tag の組合せ（例 `user_id`）が無制限だと series が爆発しメモリ・コストが破綻する。
- 「落ちない」より **「壊れずに劣化する（graceful degradation）」** が観測基盤の価値。集計が多少欠けても全体停止より良い。

制約: ローカル完結、in-memory 集計（ADR 0001）なのでメモリ上限が直接的な制約。

## 決定

**bounded channel が満杯なら block せず non-blocking drop（load shedding）し、series 数が上限に達したら新規 series を drop する。drop はすべて自己メトリクスとして計測する（dogfooding）。**

- ingest chan / sample chan は固定バッファ。`select { case ch <- x: default: atomic.AddInt64(&dropped, 1) }` で **満杯時は捨てる**。
- series registry に上限（例 10,000）。新規 series が上限超なら **そのサンプルを drop** し `dropped_cardinality++`。既存 series は影響なし。
- `dropped_ingest` / `dropped_cardinality` / `active_series` を `GET /stats` と自己メトリクスで公開し、ダッシュボードで可視化。
- `/ingest` は drop しても **202 を返す**（fire-and-forget、クライアントは成功扱い）。

## 検討した選択肢

### 1. non-blocking drop (load shedding) + series 上限 drop + 自己計測 ← 採用

- 過負荷でも **レイテンシ一定・メモリ有界**。最悪でも「一部欠測」で全体は生存。
- drop を計測して可視化することで「壊れていることが見える」。
- Go の `select { ... default: }` で素直に書け、テストで burst を入れて drop を観測できる。

### 2. block して client に backpressure（bounded queue + 送信側が詰まる）/ 429 reject

- データを失わない。送信側がレートを落とす。
- 欠点: fire-and-forget の UDP/HTTP メトリクス送信では送信側が backpressure を扱えないことが多く、詰まりが ingest handler → 上流に波及し**全体レイテンシが崩れる**。観測基盤の思想（落ちるより欠測）に反する。429 も同様にメトリクス送信側はまず無視する。

### 3. LRU evict + 無制限 queue

- 新規 series を常に受け、古い series を退避。
- 欠点: メモリ挙動が読みにくく、active な series が evict される事故が起きる。「上限超は新規を弾く」ほうが挙動が単純で学習に向く。

## 採用理由

- **学習価値**: Go の `select default` による load shedding と、backpressure を「block か drop か」で選ぶ判断軸を体得する。bounded chan のサイズ・drop 計測・cardinality cap は観測基盤の実装そのもの。
- **アーキテクチャ妥当性**: Datadog / Prometheus も高基数で series を drop・制限する（cardinality limit は実運用の中心課題）。
- **責務分離**: 「容量制約（chan / series 上限）」と「集計ロジック（ADR 0001）」を分離。drop は境界で起き、aggregator は健全なサンプルだけ見る。
- **将来の拡張性**: adaptive sampling / tag 圧縮 / per-tenant quota に発展可能。

## 却下理由

- 案 2（block / 429）: fire-and-forget メトリクスでは送信側が backpressure を扱えず、詰まりが全体に波及。観測基盤思想に反する。
- 案 3（LRU + 無制限）: メモリ挙動が読みにくく active series evict 事故。

## 引き受けるトレードオフ

- **欠測**: 過負荷時に一部サンプル/series が永久に失われる（再送なし）。観測用途では許容（傾向が見えれば良い）。drop 量を計測して可視化することで「どれだけ失ったか」は分かる。
- **cardinality 上限のチューニング**: 上限が低いと正当な series まで弾く。値は env で調整可能にし、drop 計測で気づけるようにする。
- **新規 series 優先度なし**: 上限到達後は「先着優先」。本当に重要な新 series が弾かれ得る（quota/優先度は派生 ADR）。

## このADRを守るテスト / 実装ポインタ

- `datadog/backend/internal/ingest/pipeline_test.go`（予定、`go test -race`）— バッファ超の burst を流して `dropped_ingest > 0` かつ aggregator が固まらない / 上限超 series で `dropped_cardinality > 0` かつ既存 series は集計継続。
- `datadog/backend/internal/ingest/pipeline.go`（予定）— `select { case ch <- s: default: drop }` + `atomic` counters。

## 関連 ADR

- ADR 0001: パイプライン（drop が起きる bounded chan の場所）
- ADR 0003: rollup（active_series と cardinality の永続管理）
- ADR 0004: alert（自己メトリクス drop_* に対するアラートも張れる）
