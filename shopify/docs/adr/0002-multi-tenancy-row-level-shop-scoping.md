# ADR 0002: マルチテナント分離 — `shop_id` row-level scoping

## ステータス

Accepted（2026-05-04）

## コンテキスト

Shopify は数百万のマーチャント（= Shop）を 1 つのプラットフォームに収容する典型的なマルチテナント SaaS。本プロジェクトでも「複数 Shop が同一 backend / 同一 DB を共有しつつ、互いのデータを参照できない」という前提を再現する必要がある。

主要な制約：
- ローカル完結方針のため、Shop は seed で 2〜3 件作る（例：`acme-store.localhost:3085`, `globex.localhost:3085`）
- DB は MySQL 8 単一。schema 分離・DB 分離はインフラコストの議論にすり替わるので採らない
- マルチテナント漏洩は **「他 Shop の Product / Order / Customer が見えない」**ことを RSpec で不変条件として固定
- リクエスト単位で **`current_shop` を一意に決める**仕組みが要る（サブドメイン解決 or 明示ヘッダ）

## 決定

**単一 DB + 全 tenant-aware テーブルに `shop_id` カラム + 明示的 scope (`current_shop.products`)** を採用する。

- すべての tenant-scoped table に `shop_id BIGINT NOT NULL` + `(shop_id, ...)` の複合 index を必須化
- `ApplicationRecord` 上で `belongs_to :shop` を tenant-aware concern (`TenantOwned`) で宣言
- リクエスト解決：`Rack::Request` のサブドメインから `Shop.find_by!(subdomain: ...)` で `current_shop` を確定（middleware）
- controller 層では **`Shop.current` ではなく明示的に `current_shop.products.find(id)` を強制** （default_scope は使わない、ADR 0002 補足参照）
- `App` プラットフォーム経由の API アクセスは `AppInstallation#shop` から解決（ADR 0004）

## 検討した選択肢

### 1. shop_id row-level scoping ← 採用

- 利点：MySQL 単一 DB / single migration / cross-tenant な集計（admin 用）が SQL 1 本で書ける
- 利点：Rails の関連付けを素直に使える

### 2. schema-per-tenant (PostgreSQL `SET search_path` 等)

- 利点：物理分離に近い、漏洩リスクが低い
- 欠点：MySQL は名前空間が DB レベル ≒ DB-per-tenant に近く運用コスト大、migration を全 schema に流す必要

### 3. DB-per-tenant

- 利点：完全分離、ノイジーネイバーを物理的に排除
- 欠点：本リポの目的（モジュラーモノリス + 在庫整合性）と関係ない議論に時間を取られる

### 4. `default_scope :for_current_shop` で暗黙 scope

- 利点：ボイラープレートが消える
- 欠点：`default_scope` は **`unscoped` で簡単に外せる + 関連付け経由で漏れる**（`User.find(...).orders` が tenant 跨ぎになる事故が Rails 界で頻出）。Shopify 自身も明示 scope を勧めている

## 採用理由

- **学習価値**：マルチテナント設計の論点（解決方法 / index 戦略 / 漏洩テスト）を最小コストで全部触れる
- **アーキテクチャ妥当性**：Shopify / GitHub Enterprise Cloud (org_id) / Linear (workspace_id) など実プロダクトの定番
- **責務分離**：tenant 解決は `core` Engine の middleware が一手に引き受け、他 Engine は `current_shop` を当然の入力として扱える
- **将来の拡張性**：物理分離が必要になった時は「ホットな shop だけ別 DB に切り出す」垂直分割が可能（`shop_id` を partition key として残してある前提で）

## 却下理由

- **schema/DB-per-tenant**：MySQL では運用コストが急増。本論点（モジュラー化と在庫整合）から逸れる
- **default_scope**：暗黙 scope は事故ること多数。明示 scope のボイラープレートは concern + lint で吸収する

## 引き受けるトレードオフ

- **noisy neighbor**：1 つの Shop の重いクエリが全 Shop に波及する。MVP では許容、将来的には connection pool 分離 / read replica で吸収する設計余地のみ残す
- **明示 scope のボイラープレート**：`current_shop.products.find(id)` を毎回書く。RuboCop custom cop で `Product.find` を禁止し、`current_shop.products.find` のみ許可する (将来。MVP では人手規約 + `scope_lint_spec.rb` で TenantOwned include を強制)
- **cross-tenant 集計の取り扱い**：admin 用集計は `Shop.unscoped` ではなく `AdminQuery` という別境界 (Service Object) からのみ許可。controller には漏らさない
- **`shop_id` の漏れ**：FK 違反だけでなく、`Order.where(...)` で `shop_id` 抜けの事故が起きうる。**全 tenant-scoped table に `(shop_id, ...)` 複合 index を貼り**、`scope_lint_spec.rb` で全 tenant-owned model が TenantOwned concern を include していることを fixate する
- **`accounts.email` はグローバル UNIQUE (rodauth 既定)**：rodauth の `accounts` テーブルは email UNIQUE 1 つ。すなわち「同一 buyer が複数 shop で同 email を使ってアカウントを作る」はできない。**Shopify 実プロダクトは shop ごとに customer DB が分離される設計**だが、本リポでは rodauth-rails の既定スキーマに従い 1 buyer 1 アカウントのモデルを採用する。`Core::User` 側は `(shop_id, email)` UNIQUE を持つので「異なる buyer の同 email アカウントが別 shop に存在する」ことは可能。スコープ整理:
    - `Account` (rodauth): プラットフォーム全体で 1 email 1 アカウント (グローバル UNIQUE)
    - `Core::User`: shop ごとに 1 email 1 ユーザー (`(shop_id, email)` UNIQUE)
  これは **Apps::App** (プラットフォーム global) と **AppInstallation** (shop tenant) と同じ「プラットフォーム層 / テナント層」分離パターン。派生 ADR で「マルチショップ 1 buyer モデル」をやる場合、accounts と users の関係を 1:N に拡張する

## このADRを守るテスト / 実装ポインタ

- `spec/multi_tenancy/cross_tenant_isolation_spec.rb` — Shop A のセッションで Shop B のリソース ID を直接叩いて 404 を返すこと
- `spec/multi_tenancy/scope_lint_spec.rb` — 全 tenant-scoped model が `TenantOwned` concern を include していること
- `app/models/concerns/tenant_owned.rb` — `belongs_to :shop` + `validates :shop_id, presence: true`
- `lib/middleware/tenant_resolver.rb` — サブドメインから `Shop` 解決、未解決は 404

## 関連 ADR

- ADR 0001: モジュラーモノリス（tenant 解決は core Engine が責務）
- ADR 0003: 在庫減算（在庫テーブルにも `shop_id` を必ず含めて scope する）
- ADR 0004: App プラットフォーム（App は複数 Shop に install されるので `AppInstallation#shop_id` で tenant 確定）
