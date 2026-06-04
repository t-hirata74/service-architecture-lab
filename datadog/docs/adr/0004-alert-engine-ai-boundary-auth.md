# ADR 0004: 周期評価 alert rule engine（state machine）+ ai-worker 境界 + 二経路認証

## ステータス

Accepted（2026-06-04）

## コンテキスト

datadog 固有の論点は **alert rule engine**（実運用で必ず見る）。rollup（ADR 0003）に対し閾値ルールを評価し、発火/解消を管理する。加えて、ai-worker による動的閾値（異常検知）と、**ingest（machine）と dashboard（user）で異なる認証**の扱いを決める。

制約・前提:

- ローカル完結。異常検知は実 ML を使わず ai-worker の deterministic mock。
- アラートは「一瞬の超過」で鳴らず **一定時間継続（for_duration）** で発火すべき（フラッピング抑制）。
- ingest はマシン経路（agent が API key で投げる）、dashboard/クエリ/ルール管理はユーザー経路（人が JWT で操作）。性質が違う。
- Go バックエンドなので認証は discord/uber と同じ **自前 HS256 JWT + bcrypt**（rodauth は Rails 専用）。

## 決定

**eval loop goroutine が rule を周期評価する state machine（`ok → pending → firing → ok`）+ append-only `alert_events`** を採用。ai-worker は同期 REST の動的閾値オプション（失敗は degrade）。認証は **dashboard=JWT / ingest=API key の二経路**。

- **eval loop**: ticker（例 10s）で各 `enabled` rule を直近 rollup（`window_s`）に対し評価。`comparator`（gt/lt）+ `threshold`。
- **state machine**: 条件成立 → `pending`、`for_s` 継続 → `firing`、解消 → `ok`（firing からは `resolved`）。遷移ごとに **append-only `alert_events`**（readonly 強制、zoom HostTransfer と同形）。
- **ai-worker 境界**: rule が `dynamic` 型なら `/detect-anomaly` を `X-Internal-Token` で同期 call し動的閾値を得る。ai-worker 不通/エラーは **静的 threshold のみで継続（graceful degradation、uber 同方針）**。
- **認証**: `/ingest` は `X-API-Key`（`api_keys` テーブルの hash 照合、machine 経路）。`/query` `/alerts/*` `/metrics` `/stats` は `Authorization: Bearer <JWT>`（user 経路）。policy「user 認証は最小 1 経路」を満たしつつ、ingest は内部 trusted ingress（uber の `X-Internal-Token` と同系）。

## 検討した選択肢

### 1. 周期評価 state machine + append-only events + 二経路認証 ← 採用

- 周期評価は rollup（既に窓集約済み）と相性が良く、フラッピング抑制（for_duration）を素直に書ける。
- state machine + append-only events は本リポ横断パターン（zoom 長寿命 / 監査）の短寿命・周期版。
- ingest と user で認証を分けるのは実プロダクト通り（agent は API key、人は JWT）。

### 2. 即時評価（ingest 時に rule を都度チェック）

- アラートのレイテンシが最小。
- 欠点: 高スループット ingest のホットパスに rule 評価を載せると pipeline（ADR 0001）を汚し、backpressure 設計と競合。for_duration の継続判定も持ちにくい。周期評価が観測基盤の定石。

### 3. push 評価（rollup flush をトリガに評価）

- flush 駆動でやや効率的。
- 欠点: flush と eval が密結合し、複数 resolution / 複数 rule の協調が複雑。独立した eval loop のほうが疎結合でテストしやすい。

### 4. 単一認証経路（ingest も JWT）

- 経路が 1 本で単純。
- 欠点: メトリクス agent に人間用 JWT を持たせるのは不自然（失効/ローテーション運用が違う）。machine は API key が実態に合う。

## 採用理由

- **学習価値**: alert の `ok/pending/firing` state machine + for_duration、append-only event、ai-worker の同期境界 + degrade、machine/user の認証分離を一通り学べる。
- **アーキテクチャ妥当性**: Prometheus Alertmanager / Datadog monitor と同じ「周期評価 + for + フラッピング抑制」。
- **責務分離**: ingest pipeline（ADR 0001）と alert eval を別 goroutine に分離。互いのレイテンシに干渉しない。
- **将来の拡張性**: 複合条件 / 通知チャネル / silence / 動的閾値の本格化（ai-worker 差し替え）に発展可能。

## 却下理由

- 案 2（即時評価）: ingest ホットパスを汚し backpressure 設計と競合、for_duration を持ちにくい。
- 案 3（push 評価）: flush と密結合で協調が複雑。
- 案 4（単一認証）: machine に人間 JWT は運用不自然。

## 引き受けるトレードオフ

- **評価レイテンシ = tick 間隔**: 最悪 1 tick 分アラートが遅れる（観測用途で許容）。
- **at-least-once な eval**: tick の重複/再起動で同一遷移が二重記録され得る。`alert_events` は append-only なので「同じ state への連続遷移は記録しない」ガードで抑制（冪等は state 比較で担保）。
- **API key の単純さ**: MVP は hash 照合のみ（スコープ/レート制限なし）。本番は per-key quota（派生）。
- **ai-worker 依存の任意性**: dynamic アラートは ai-worker 不在だと静的にフォールバック（精度は落ちるが鳴り続ける）。

## このADRを守るテスト / 実装ポインタ

- `datadog/backend/internal/alert/engine_test.go`（予定）— 1 窓成立で pending / for_s 継続で firing / 解消で resolved、連続同一遷移を二重記録しない。
- `datadog/backend/internal/alert/engine.go`（予定）— eval loop + 遷移マップ + append-only insert。
- `datadog/backend/internal/auth/`（予定）— JWT（user）+ API key（ingest）の 2 経路。
- ai-worker degrade は [operating-patterns.md](../../docs/operating-patterns.md) の graceful degradation に準拠。

## 関連 ADR

- ADR 0001: pipeline（eval は別 goroutine で干渉しない）
- ADR 0003: rollups（eval の入力）
- ADR 0002: 自己メトリクス drop_* にもアラートを張れる
