# ADR 0003: 在庫の同時減算整合性 — 条件付き UPDATE + ledger

## ステータス

Accepted（2026-05-04）

## コンテキスト

EC ドメインの中核論点が「**並行する複数の checkout が同じ Variant の在庫を減算した時に、負在庫を絶対に作らない**」という整合性問題。Shopify のフラッシュセール時の同時購入や、複数 App 経由の在庫操作（Shipping App + POS + Storefront）がぶつかる場面を再現したい。

制約：
- 単一 MySQL 8、Redis は使わない（reddit と同様、整合性の責務は DB に集約する）
- Solid Queue（DB-driven）でジョブも DB 上、つまり **整合性の境界は MySQL のトランザクション**で完結させたい
- 「**単に動く**」だけでなく、**スループットと負在庫防止のトレードオフ**を ADR で記録することが学習目的
- `inventory` Engine が単独で責務を持つ（ADR 0001 の依存方向）

## 決定

**条件付き UPDATE (compare-and-decrement) + `stock_movements` ledger** を採用する。

- 在庫減算は **`UPDATE inventory_levels SET on_hand = on_hand - :qty WHERE variant_id = :v AND location_id = :l AND on_hand >= :qty`** を発行
- `affected_rows == 1` を確認、0 なら `Inventory::InsufficientStock` を raise（同一トランザクションで rollback）
- 同一トランザクションで `stock_movements` (append-only ledger) に `{variant_id, location_id, delta, reason, source_id}` を INSERT
- 集計値 (`InventoryLevel#on_hand`) と ledger 合計の整合性は ai-worker の reconcile ジョブで日次照合（drift があれば slack 通知をモック）
- checkout フローは `Orders::CheckoutService` から `Inventory::DeductService.call(...)` を**同一 Order トランザクション内**で呼ぶ

## 検討した選択肢

| 案 | 利点 | 欠点 | 採否 |
| --- | --- | --- | --- |
| **条件付き UPDATE + ledger** | DB 1 本で原子性、retry 不要、ledger で監査と reconcile 両取り | sellable_quantity 等の派生値は別途維持 | ✅ 採用 |
| `with_lock` (悲観ロック / `SELECT ... FOR UPDATE`) | 直感的、retry なし | 同一 Variant の checkout が直列化、フラッシュセール時にスループット劣化 | ❌ |
| 楽観ロック (`lock_version`) | 衝突は明示 | 衝突時の retry ループ実装が必要、UX で「在庫切れ」と「retry してね」を区別しづらい | ❌ |
| Redis `DECRBY` で reservation | 高速、Redis pattern の学習 | DB と Redis の二重 truth、再起動で消える、本リポの「Redis 不使用」原則に反する | ❌ |
| MySQL CHECK 制約 (`on_hand >= 0`) | 物理ガード | MySQL 8 で CHECK は機能するが、エラー型がアプリ層で扱いにくく、partial decrement が破綻 | ❌ 補助としてのみ採用検討 |

## 採用理由

- **学習価値**：「同時減算」という EC の典型問題を **悲観ロックに頼らず DB 1 本で解く**という設計判断が手に入る。本リポの reddit (ADR 0002 の score 相対加算) との対比が成立する
- **アーキテクチャ妥当性**：`UPDATE ... WHERE col >= n` パターンは在庫管理 / クレジット消費 / レート制限など多くの実プロダクトで採用されている定番
- **責務分離**：`Inventory::DeductService` が唯一の減算経路。controller / job からはここを経由する以外に在庫を触れない
- **将来の拡張性**：複数 location（warehouse / store / dropship）対応は `(variant_id, location_id)` の複合 PK で素直に拡張。ledger があるので将来の forecasting / cycle count にも使える

## 却下理由

- **悲観ロック**：単純だが「同一 SKU への同時注文」がボトルネック。これは Shopify が実プロダクトで悲観ロックを避けている理由でもある（実装パターンは公開されている）
- **楽観ロック**：retry 制御の複雑さがアプリ層に漏れる。本論点（整合性）よりリトライ戦略の議論にすり替わる
- **Redis reservation**：本リポは「整合性は DB に集約」原則を一貫させたい

## 引き受けるトレードオフ

- **派生集計値**：`sellable_quantity = on_hand - reserved` のような派生値は別カラム or view で維持する必要。MVP では `on_hand` のみ扱い、`reserved`（カート滞留）は派生 ADR 候補
- **ledger 肥大化**：`stock_movements` は append-only なので長期で巨大化する。MVP では partition / archival は扱わず ADR 派生候補
- **drift 検出**：条件付き UPDATE は強いが、`InventoryLevel.on_hand` を経由しない直接 SQL や手動操作で drift する可能性は残る。**ai-worker の `reconcile_inventory` バッチ**で日次照合し、差分があれば warning（reddit ADR 0002 と同じ truth + reconcile パターン）
- **partial decrement なし**：「3 個欲しいが 2 個しかないので 2 個だけ売る」は採らない。**all-or-nothing**。partial が必要になったら別 ADR

## このADRを守るテスト / 実装ポインタ

- `spec/inventory/concurrent_deduct_spec.rb` — 100 並行 thread から 1 SKU を decrement、`on_hand` 一貫性 + 失敗回数を検証
- `spec/inventory/ledger_consistency_spec.rb` — `SUM(stock_movements.delta) + initial == on_hand` の不変条件
- `components/inventory/app/services/inventory/deduct_service.rb` — 唯一の減算経路
- `components/inventory/app/models/inventory/stock_movement.rb` — append-only（`readonly?` を override で全 update を拒否）

## 関連 ADR

- ADR 0001: モジュラーモノリス（inventory Engine が単独責務）
- ADR 0004: App プラットフォーム（在庫変更イベントを `inventory.updated` webhook として配信）
- 派生候補：reservation / cart hold / 複数 location アロケーション戦略
