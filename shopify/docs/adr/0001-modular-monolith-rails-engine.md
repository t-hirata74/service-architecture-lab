# ADR 0001: モジュラーモノリス — Rails Engine + packwerk による境界分割

## ステータス

Accepted（2026-05-04）

## コンテキスト

Shopify が実プロダクトで採用していることで知られる「モジュラーモノリス」（Component-Based Rails Monolith）を、本プロジェクトの中核学習テーマに据える。単一の Rails アプリケーション内に **論理的な境界**を引き、依存方向を強制し、将来サービス抽出が必要になった時にコストを最小化する設計を実装で再現したい。

本リポジトリの他プロジェクト (slack / youtube / github) は単一 Rails app + namespace で十分だった（ドメイン境界が浅い）。一方 Shopify 風の EC ドメインは **Catalog (商品) / Inventory (在庫) / Orders (注文・チェックアウト) / Apps (拡張プラットフォーム)** という独立性の高い 4 つの境界を持ち、namespace 規約だけでは「Order が Inventory の内部 model を直接参照する」「Apps が Orders の controller を呼ぶ」といった**境界侵食**が起きやすい。

制約：
- ローカル完結方針 → マイクロサービス分割は不可（compose で複数 Rails を立てるのは学習価値より運用コストが大きい）
- Rails 8 標準（rodauth-rails / Solid Queue）に乗る
- 「単一プロセス・単一 DB」を前提にしつつ、Engine 間で **in-process 同期呼び出し**を許容する代わりに、**境界違反は CI で落とす**

## 決定

**Rails Engine + packwerk** で 5 つの Component に分割する。各 Component は独立した Engine ディレクトリ (`components/<name>/`) に置き、`packwerk` で依存方向を静的検証する。

- `components/core/` — `Shop`, `User`, 認証 (rodauth)、テナント解決
- `components/catalog/` — `Product`, `Variant`, `Collection`
- `components/inventory/` — `InventoryItem`, `InventoryLevel`, `StockMovement` (ADR 0003)
- `components/orders/` — `Cart`, `Checkout`, `Order`, `LineItem`
- `components/apps/` — `App`, `AppInstallation`, `WebhookSubscription`, `WebhookDelivery` (ADR 0004)
- 境界規約：各 Component は `package.yml` で **公開 API (public/) のみ** 露出。internal 直参照は packwerk violation
- 依存方向：`apps → orders → inventory → catalog → core`（逆参照禁止）

## 検討した選択肢

### 1. Rails Engine + packwerk ← 採用

- Component 単位で routes / models / controllers / migration をディレクトリ的に隔離
- `packwerk` で依存グラフを CI 失敗にできる（実行時境界ではないが、コードレビュー前に検出）
- Shopify 自身が公開している事例と最も近い

### 2. 単一 Rails app + namespace のみ

- 利点：シンプル、立ち上がりが速い
- 欠点：規約のみで実行時/CI で強制されない。半年で境界が崩れるのは他プロジェクトで実体験済み

### 3. マイクロサービス（compose で複数 Rails）

- 利点：物理境界、サービス間契約が明示
- 欠点：本リポのローカル完結・学習効率方針と相性が悪い。トランザクション境界が分散し、本来の論点（モジュラー化の利点）から逸れる

### 4. sorbet / RBS による型ベース境界

- 利点：型レベルで API を絞れる
- 欠点：型が無い箇所の境界はガードできない。Rails 8 への型導入コストが本論点を上回る

## 採用理由

- **学習価値**：本リポで唯一「Rails の境界設計」を正面から扱うプロジェクト。他の Rails 実装 (slack/youtube/github) との対比で「いつ Engine 分割を始めるか」の判断軸が手に入る
- **アーキテクチャ妥当性**：Shopify / GitHub / Gusto などが実プロダクトで採用している実績ある形
- **責務分離**：物理境界を持たないので分散トランザクションを避けつつ、CI で論理境界を守る
- **将来の拡張性**：いずれの Engine も `engine.rb` の mount を解除して別 Rails app に切り出せる。`packwerk` で「現在の依存」が見えるので抽出の影響範囲が事前に分かる

## 却下理由

- **namespace のみ**：規約は腐敗する。CI ガードのない境界は半年で崩れる
- **マイクロサービス**：今のスコープでは over-engineering、トランザクション境界の議論が本論点を覆い隠す
- **sorbet**：境界定義に型を使うのは可能だが、Rails 8 + Rodauth + Solid Queue との型整備コストが学習効率を下回る

## 引き受けるトレードオフ

- **Engine 間 in-process 同期呼び出し**：例えば `Orders::CheckoutService` から `Inventory::DeductService.call(...)` を直接呼ぶ。将来別サービスに切り出す時はここに gRPC/HTTP 境界が立つ。**今はインターフェースだけ Service Object 化して呼び出し位置を絞る**
- **DB スキーマは単一**：各 Component の table prefix で論理分離 (`catalog_products`, `orders_orders`)。物理的には JOIN 可能なので、それを **packwerk + ApplicationRecord 規約** で防ぐ
- **packwerk の運用コスト**：違反を許容する `package_todo.yml` の運用が必要。導入時は ignore で済ませず、初期から zero-violation を維持する
- **`enforce_privacy` (公開 API 制約) は本 Phase では採用しない**：packwerk 3 で `enforce_privacy` は `packwerk-privacy` gem に分離された。Phase 5 までは `enforce_dependencies` のみで「どの方向に依存できるか」を縛り、「Engine の internal を外から触る」の禁止 (`public/` ディレクトリで API を絞る) は派生 ADR に倒す。Engine 間の interface は **Service Object (`Apps::EventBus.publish` / `Inventory::DeductService.call`) に集約**することで人手規約として担保する
- **`core` Engine が抱える top-level クラス**：`ApplicationController` / `ApplicationJob` / `Account` (rodauth が解決する定数) / `TenantOwned` concern は core Engine 配下に置きつつトップレベル namespace で定義する。これは「他 Engine から ::ApplicationController として継承できる必要がある」「rodauth が `Account` をトップレベル lookup する」という外部規約に従う形であり、core Engine が**プラットフォームの基盤層**として top-level スロットを持つことを許容する

## このADRを守るテスト / 実装ポインタ

- `bin/packwerk check` を CI に組み込み、依存方向違反をビルド失敗にする
- `components/<name>/package.yml` の `enforce_dependencies: true` を全 Engine で必須化
- `spec/architecture/dependency_spec.rb` — packwerk violations が 0 件であることを RSpec で再表現（CI ログより読みやすい形）

## 関連 ADR

- ADR 0002: マルチテナント分離（`shop_id` scope は core Engine が責務を持つ）
- ADR 0003: 在庫の同時減算（inventory Engine が単独で責務を持つ前提）
- ADR 0004: App プラットフォーム（apps Engine が orders/inventory のイベントを subscribe する）
