# ADR 0002: append-only op log + materialized state（per-prop Lamport clock）

## ステータス

Accepted（2026-06-03）

## コンテキスト

ADR 0001 で「Server 権威 + per-property LWW-Register」を採った。これを **MySQL にどう格納するか**が本 ADR の論点。要件:

- **収束**: 各プロパティの LWW 判定に `(lamport, actor_id)` が要る（ADR 0001）。
- **総順序**: server が op に単調増加の `seq` を付け、配信安定化・**遅延 join の catch-up（`?since=seq`）**・dedup を可能にする。
- **初期ロードの速さ**: 新規 join / server 再起動時に「全 op をリプレイ」せず、**現在状態の snapshot** を即返したい。
- **監査**: 誰がいつ何を変えたかの履歴（負けた op も含む）を残したい。

制約: ローカル完結（MySQL 8 のみ、外部 KVS なし）。Rails 8 の Active Record + JSON 列で表現する。

## 決定

**append-only `operations` log（server 採番 `seq`）+ materialized `canvas_objects`（per-prop Lamport clock）の二層** を、**1 トランザクションで原子更新**する。

- `operations`（append-only、不変）: `document_id`, `seq`（= commit 時の `documents.version`）, `actor_id`, `object_id`, `op_type`, `payload` JSON, `lamport`, `created_at`。`(document_id, seq)` UNIQUE。
- `canvas_objects`（materialized 現在状態）: `document_id`, `object_id`, `kind`, `props` JSON, **`prop_clocks` JSON**（`{"x": {"l":12,"a":3}, "fill": {"l":9,"a":1}, "deleted": {"l":5,"a":2}}`）, `z_index`, `last_seq`, timestamps。`(document_id, object_id)` UNIQUE。
- `documents.version` BIGINT を **`with_lock` で原子採番**（`version += 1` → その値が op の `seq`）。github の番号空間共有 / zoom の state machine と同じ `with_lock` パターン。
- **適用ロジック（OperationApplier、1 txn）**:
  1. `documents` 行を lock、`version += 1` で `seq` 確定。
  2. `operations` に INSERT（seq, lamport, payload）。
  3. `payload` の各プロパティを LWW 比較し、勝ったものだけ `canvas_objects.props` / `prop_clocks` を更新（`last_seq = seq`）。
  4. COMMIT 後に ActionCable broadcast（ADR 0003）。

## 検討した選択肢

### 1. op log + materialized state の二層 ← 採用

- snapshot（`canvas_objects`）で初期ロードが速い。op log（`operations`）で catch-up / 監査 / 順序が取れる。
- 「歴史（log）」と「現在（materialized）」を分けることで、両方の要件を素直に満たす。
- shopify の `inventory_levels`（現在状態）+ `stock_movements`（append-only ledger）と同じ二層思想。

### 2. event-sourced 完全リプレイ（log のみ、materialized を持たない）

- 真実は 1 つ（op log）だけで美しい。状態は常に fold で導出。
- 欠点: ロード毎に全 op を replay するコストが線形に増える。スナップショット最適化を結局足すことになり、案 1 に収束する。

### 3. columns-only（clock を持たず `canvas_objects` の列を直接 UPDATE）

- 最小スキーマ。
- 欠点: LWW 判定に必要な `(lamport, actor)` を保持できず、**ADR 0001 の収束が成立しない**（後着の古い op が新しい値を踏み潰す）。却下。

## 採用理由

- **学習価値**: 「append-only log + materialized projection」という実務頻出パターンを、CRDT の clock 保持と組み合わせて実装できる。`seq`（log の順序）と `lamport`（収束の時計）を**別カラムに分けて持つ**設計が手で書ける。
- **アーキテクチャ妥当性**: log + snapshot は協調編集・イベントソーシングの定石。Figma も op log + 定期 snapshot を持つ。
- **責務分離**: `operations` は不変・追記のみ、`canvas_objects` は LWW projection。読み（snapshot / catch-up）と書き（apply）の経路が明確。
- **将来の拡張性**: snapshot を定期 checkpoint 化（古い op を圧縮）や、`prop_clocks` のテキスト列だけ sequence CRDT 化、に発展できる。

## 却下理由

- 案 2（完全リプレイ）: ロードコストが op 数に線形。snapshot を足すと案 1 になる。
- 案 3（columns-only）: clock を持てず ADR 0001 の収束が壊れる。

## 引き受けるトレードオフ

- **二重書き込み**: 1 op で `operations` INSERT と `canvas_objects` UPSERT の両方を書く（1 txn で原子性は担保）。
- **JSON 列の制約**: `props` / `prop_clocks` を JSON で持つため、特定プロパティでの検索・集計は弱い（図形編集では不要なので許容）。
- **`documents.version` の lock 競合**: 同一ドキュメントへの並行 op は version 行で直列化される。1 ドキュメントの同時編集者数が MVP 規模なら問題なし。高頻度時は op バッチ化（client 側 coalesce）で緩和。
- **log の肥大**: `operations` は無限追記。MVP では放置、本番は checkpoint + 古い op truncate（派生）。

## このADRを守るテスト / 実装ポインタ

- `figma/backend/spec/services/operation_applier_spec.rb`（予定）— 1 txn で seq 採番 + LWW projection が原子的、negative case（古い lamport は materialize されないが log には残る）。
- `figma/backend/app/models/document.rb`（予定）— `with_lock { increment!(:version) }` で seq 採番。
- `figma/backend/app/models/operation.rb`（予定）— `readonly?` で append-only を強制（zoom の HostTransfer と同方針）。

## 関連 ADR

- ADR 0001: 整合性モデル（per-prop LWW、2 つの時計の分離）
- ADR 0003: 配信（COMMIT 後に op を ActionCable broadcast、catch-up は REST `?since=seq`）
