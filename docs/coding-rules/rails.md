# Rails コーディング規約

`slack/backend/` で実際に採用している規約を共通ルールとしてまとめる。

---

## 技術スタック

- Rails 8 (API mode) / Ruby 3.3
- DB: MySQL 8 / Cache & Queue: solid_cache + solid_queue（DB-backed）
- リアルタイム: ActionCable + Redis Pub/Sub adapter
- 認証: rodauth-rails + JWT (cookie / session を使わない)
- Lint: `rubocop-rails-omakase`
- 静的解析: brakeman（CI で実行）
- テスト: **RSpec (rspec-rails) + FactoryBot**（共通方針）。詳細は [`docs/testing-strategy.md`](../testing-strategy.md)

---

## Lint / Style

- `.rubocop.yml` は `inherit_gem: rubocop-rails-omakase` をベースとし、必要最小限の override に留める
- 文法の好みでルールを上書きしない。Omakase の判断に乗る
- `bundle exec rubocop` のエラーは push 前に解消する

---

## API モード前提のルール

- `ApplicationController < ActionController::API`（views / cookies / CSRF を持たない）
- レスポンスは JSON 一択。テンプレート / view を生やさない
- CORS は `rack-cors` で `config/initializers/cors.rb` に集約

---

## 認証 (rodauth + JWT)

- すべてのプロジェクトで認証手段は **1 経路のみ**（メール+パスワード）。OAuth/SAML/2FA は範囲外
- rodauth は **JWT モードのみ有効**（`enable :jwt`）。`:remember` などの cookie 系は無効
- `only_json? true`、`require_password_confirmation? false`（confirm はクライアント側）
- `account` (rodauth が管理) と `user` (アプリのドメイン) はテーブル分離。`account.id == user.id` を `after_create_account` フックで揃える
- パスワードは min 8 / max 72 bytes（OWASP 準拠）
- JWT secret は `Rails.application.secret_key_base` から取得

---

## Controller

- 1 controller = 1 リソース。ネストは `messages_controller.rb` のようにフラットに保つ
- `before_action` で 認証 / リソース引き当てを行う
- **シリアライザ gem は導入しない**。controller 内に `serialize_message` のようなプライベートメソッドを書く（学習プロジェクトでは見通しが優先）
- ページネーションは **cursor 方式**（`before` パラメータ + limit cap）。offset は使わない
- エラーは `rescue_from` または個別 `rescue` で `render json: { error: ... }, status: :xxx`

例:
```ruby
class MessagesController < ApplicationController
  before_action :require_authentication
  before_action :load_channel

  def index
    limit = params[:limit].to_i.clamp(1, 100)
    scope = @channel.messages.active.order(id: :desc).limit(limit)
    scope = scope.where("id < ?", params[:before]) if params[:before].present?
    render json: scope.map { serialize(_1) }
  end
end
```

---

## Model

- 論理削除は `deleted_at` カラム + `scope :active` パターン
- 不変条件はモデル層で守る（例: 既読 cursor の単調増加 `advance_read_cursor!(id)` は `cursor < id` の時のみ更新）
- `validates` を必ず書く（`presence`, `length`, `uniqueness` など）
- callback は最小限。複雑なロジックは `app/services/` に出す

---

## ADR からのコメント参照

実装が ADR で定めた挙動を担っている場合、controller / model に **ADR 番号を 1 行コメント**しておく:

```ruby
# ADR 0002: 既読 cursor は単調増加（巻き戻し禁止）
def advance_read_cursor!(message_id)
  ...
end
```

---

## Service オブジェクト (`app/services/`)

- 外部 HTTP 呼び出し / 複雑な多モデルにまたがる処理に使う
- `Net::HTTP` ベースで十分。`faraday` 等の追加依存はビジネス上の理由が無ければ入れない
- タイムアウトは必ず明示（例: open=2s / read=10s）
- 例: `AiWorkerClient` は Python (FastAPI) を呼ぶラッパー。URL は `ENV.fetch("AI_WORKER_URL", "http://localhost:8010")`

### ai-worker 境界（共通方針）

slack と youtube で同じパターンが独立に発生したので、共通ルールに昇格する。

1. **失敗時は本流を止めない**: ai-worker への HTTP 呼び出しは **graceful degradation** を前提に書く。サーバ落ち / タイムアウト / 5xx でも、UI は基本機能（一覧・詳細）が動き続ける
2. **エラー型は3種**: `Client::Error` (本流非破壊で握れる) / `Client::Timeout` (Error の派生) / それ以外は `raise`
3. **ジョブ呼び出しは noop でログ警告のみ**:
   ```ruby
   def perform(video_id)
     ...
     AiWorkerClient.extract_tags(...)
   rescue AiWorkerClient::Error => e
     Rails.logger.warn("ExtractTagsJob video##{video_id} skipped: #{e.message}")
   end
   ```
4. **コントローラ呼び出しは `200 + degraded: true`**:
   ```ruby
   render json: { items: [], degraded: true }, status: :ok
   ```
5. **テストは WebMock で実 HTTP を遮断**: `WebMock.disable_net_connect!(allow_localhost: true)` を `rails_helper.rb` で有効化。各 spec で `stub_request` を明示
6. **タイムアウト**: `open_timeout = 2`、`read_timeout = 10`（学習用途。本番は ADR で）
7. **境界は Service オブジェクトに集約**: コントローラ / ジョブから直接 `Net::HTTP` を叩かない

### Job の原子的 enqueue

state machine + job enqueue を「同時に成立 / 同時に成立しない」で揃えたい場合:

- **Rails 8.1 で `config.active_job.enqueue_after_transaction_commit` の global 設定が deprecated**。代わりに **`ApplicationJob` 側で**:
  ```ruby
  class ApplicationJob < ActiveJob::Base
    self.enqueue_after_transaction_commit = true
  end
  ```
- これにより `Video.transaction { update!(...); SomeJob.perform_later(id) }` で
  rollback 時にジョブが enqueue されない / commit 後に enqueue される
- multi-DB 跨ぎの分散トランザクションは張れないが、**ジョブ先行 → DB rollback の事故は防げる**

---

## Migration / Schema

- migration ファイル名は `YYYYMMDDHHmmss_create_xxx.rb`（Rails 標準）
- `db/schema.rb` をコミット
- 不可逆な migration（データ移行など）は `up` / `down` を両方書く
- **MySQL の `TEXT` カラムに `default:` は付けられない**: `default: ""` は migration が落ちる。`null: false` だけにし、デフォルトは Active Record バリデーションか `default_scope` 側で持つ

---

## Rails 8 の隠れた挙動

### enum の `pluck` は文字列を返す

Rails 8 で `enum :state, { open: 0, closed: 1 }` を引いた `pluck(:state)` は **整数ではなく文字列ラベル** (`"open"` / `"closed"`) を返す。
よくやる事故:

```ruby
# ❌ Rails 7 までの感覚で int を期待すると nil → to_sym で例外
Issue.where(...).pluck(:state).map { |s| Issue.states.key(s).to_sym }

# ✅ 文字列のまま比較する。`Klass.states[:open]` の整数も受けるので片方統一する
Issue.where(...).pluck(:state).map(&:to_s)
```

`.where(state: :open)` / `.where(state: "open")` は両方通るので、フィルタ側は ENUM 値をそのまま渡せばよい (内部で int に変換される)。
実例: `github/backend/app/services/permission_resolver.rb`, `github/backend/app/models/pull_request.rb#aggregated_check_state`。

### enum キーの衝突回避

同じモデル内に複数の `enum` を持つ場合、key は **モデル全体で一意**でないといけない。
例えば `state: merged` と `mergeable_state: merged` は衝突するので Rails 側は `merged_state` にして、GraphQL / API 表層では `merged` に再マップする。
→ ADR / コードコメントに「なぜ key が ugly なのか」を残す。実例: `github/backend/app/models/pull_request.rb`。

---

## 連番採番 (`with_lock` パターン)

リポジトリ内で一意な番号 (Issue/PR の `#1`, `#2`, ...) や slug を採番するときは、専用の counter 表 + 行ロックで直列化する。

```ruby
# ADR 0003 (github)
class IssueNumberAllocator
  def self.next_for(repository)
    counter = RepositoryIssueNumber.find_or_create_by!(repository_id: repository.id)
    counter.with_lock do
      counter.update!(last_number: counter.last_number + 1)
      counter.last_number
    end
  end
end
```

- `find_or_create_by!` は **lock の外**で起きるので、最初の 2 リクエストが衝突する。**unique 制約**が最後のセーフティネット
- transactional fixtures は同じ接続を使うので RSpec 内では真の並行性をテストできない。`expect_any_instance_of(...).to receive(:with_lock)` で意図確認するに留める

### 親レコード上の counter カラム (シンプル版 / shopify)

per-tenant な per-shop counter なら、専用 counter 表を作らず **親 (`shops`) に `next_order_number` カラムを 1 個追加**するだけで足りる:

```ruby
# shopify ADR 0003 + I3 review fix
def allocate_order_number!
  shop = Core::Shop.where(id: @cart.shop_id).lock.first!  # SELECT FOR UPDATE
  number = shop.next_order_number
  shop.update!(next_order_number: number + 1)
  number
end
```

- **`SELECT MAX(number) FOR UPDATE` は採らない**。MySQL InnoDB の next-key lock + gap lock の挙動に依存して "たまたま" 直列化されるだけで、Postgres など他 DB では破綻する。明示的な counter カラム + `lock` の方が読みやすく可搬
- counter 表を別に立てるか親に持たせるかは、「採番対象が 1 リソース型 (Issue/PR の番号空間共有 = 別表) か、親リソースの 1 属性 (Order#number = 親 (Shop) 属性) か」で決める

実例: `github/backend/app/services/issue_number_allocator.rb` / `shopify/backend/components/orders/app/services/orders/checkout_service.rb#allocate_order_number!`。

---

## モジュラーモノリス (Rails Engine + packwerk)

ドメイン境界が浅いプロジェクト (slack/youtube/perplexity) では namespace で十分だが、**境界の独立性が高いドメイン** (shopify の catalog / inventory / orders / apps) では Rails Engine + packwerk で「依存方向を CI で強制」する選択肢がある。判断軸は ADR 0001 (shopify) を参照。

### Engine 配置の落とし穴

`isolate_namespace Foo` 配下の autoload は `app/*/foo/` 配下を `Foo::*` として解決する。一方、**top-level 定数** (`ApplicationRecord`, `ApplicationJob`, `ApplicationController`, `Account` (rodauth が解決)) は `app/*/` 直下に置く必要がある。

主 app の `app/` ディレクトリに置くと、Engine から参照したときに **packwerk dependency violation** になる (`'.' (root) に依存していない` と怒られる)。**core Engine の `app/` 直下に集約する**:

```
components/core/
  app/
    controllers/application_controller.rb   # ← top-level: 全 Engine の controller 親
    jobs/application_job.rb                  # ← top-level: 全 Engine の Job 親
    models/account.rb                        # ← top-level: rodauth が解決する定数
    models/concerns/tenant_owned.rb          # ← top-level concern
    models/core/shop.rb                      # ← Core::* (engine namespace)
    models/core/user.rb
    models/core/application_record.rb        # ← Core::ApplicationRecord (Engine local abstract)
```

その上で `package.yml` に `dependencies: []` (core) を書けば、他 Engine が `< ApplicationController` してもよい (root から見れば core への依存はない、core から見れば top-level 定数を提供しているだけ)。

### `enforce_dependencies` のみ採用、`enforce_privacy` は派生 ADR

packwerk 3 で `enforce_privacy` (公開 API のみ露出) は別 gem (`packwerk-privacy`) に分離された。MVP では `enforce_dependencies: true` のみで「方向」を縛り、Engine の internal を外から触る禁止は **Service Object に集約 (人手規約)** で代替。`Apps::EventBus.publish` / `Inventory::DeductService.call` のような明確な entry point を 1 ファイルに集めることで、外部から呼ぶ場所を grep 1 発で見つけられるようにする。

### Engine 間 dependency inversion: ActiveSupport::Notifications

依存方向 `apps → orders` のもとで、**逆向きの通知** (`orders` の業務イベントを `apps` の webhook 配信が拾う) を実装したい場合、orders から apps を直接呼べない。Rails 標準の `ActiveSupport::Notifications` で pub/sub する。

```ruby
# orders/app/services/orders/checkout_service.rb
ActiveSupport::Notifications.instrument("orders.order_created", shop: @cart.shop, payload: { ... })

# apps/lib/apps/engine.rb
config.after_initialize do
  ActiveSupport::Notifications.subscribe("orders.order_created") do |*, payload|
    Apps::EventBus.publish(topic: :order_created, payload: payload[:payload], shop: payload[:shop])
  end
end
```

特性:
- subscriber は **同期実行** で publish 元の transaction に乗る (webhook 配信 INSERT も同じ tx 内で原子的)
- subscriber 内で raise すれば caller (checkout) を rollback させられる → at-least-once 保証の代償
- packwerk から見ると orders は apps を一切参照していない (依存方向 fixate)

実例: `shopify/backend/components/orders/app/services/orders/checkout_service.rb` + `shopify/backend/components/apps/lib/apps/engine.rb`。

---

## マルチテナント (`shop_id` row-level scoping)

`shop_id` を全 tenant-scoped table に必ず持たせ、`current_shop.products.find(id)` のように **明示 scope** を controller / service で必ず通す。`default_scope` は採らない (`unscoped` で外せる + 関連付け経由で漏れる事故が多い)。

### TenantOwned concern + scope_lint spec で fixate

```ruby
# components/core/app/models/concerns/tenant_owned.rb
module TenantOwned
  extend ActiveSupport::Concern
  included do
    belongs_to :shop, class_name: "Core::Shop"
    validates :shop_id, presence: true
  end
end

# 全 tenant-owned model がこれを include していることを spec で固定
RSpec.describe "Tenant-owned models lint" do
  TENANT_OWNED_MODELS = [Core::User, Catalog::Product, ...].freeze
  TENANT_OWNED_MODELS.each do |klass|
    it "#{klass.name} は TenantOwned を include している" do
      expect(klass.included_modules).to include(TenantOwned)
    end
  end
end
```

### 「1 active per X」UNIQUE のための `active_marker` パターン

「customer 1 人 = open cart 1 つ / completed cart は何個でも」のような **status 依存の UNIQUE** を MySQL で表現したい時、partial UNIQUE index は標準では使えない。**`active_marker` カラム (active 時 1, それ以外 NULL)** + `(scope_cols, active_marker)` UNIQUE で実現する:

```ruby
# migration
add_column :orders_carts, :active_marker, :integer
add_index :orders_carts, [:shop_id, :customer_id, :active_marker], unique: true

# model: status と active_marker を sync
class Cart
  enum :status, { open: 0, completed: 1, abandoned: 2 }
  before_validation { self.active_marker = open? ? 1 : nil }
end
```

MySQL の UNIQUE は **複数 NULL を許容**するので、completed/abandoned cart は何個でも作れる一方、open は 1 つしか作れない。Postgres なら partial UNIQUE index でもっと素直に書ける。

### `find_or_create_by!` の race と retry idiom

UNIQUE 制約が立っていれば、並行リクエストでの `find_or_create_by!` race を **1 回 retry** で吸収できる:

```ruby
def current_open_cart
  attempts = 0
  begin
    attempts += 1
    Orders::Cart.find_or_create_by!(shop_id: ..., customer_id: ..., status: :open)
  rescue ActiveRecord::RecordNotUnique
    retry if attempts < 2
    raise
  end
end
```

UNIQUE 制約**なしの**場合、`find_or_create_by!` は race するとサイレントに重複行を作るので、必ず DB 制約とセットで使う。

### TOCTOU 防止の `lock!`

「cart が `:open` であること」をチェックしてから `:completed` に更新するような **time-of-check vs time-of-use** な経路では、トランザクション開始直後に `record.lock!` で SELECT FOR UPDATE を取り、ロック取得後に再評価する:

```ruby
def call
  Order.transaction do
    @cart.lock!  # SELECT ... FOR UPDATE
    raise CheckoutError, "cart is not open" unless @cart.open?
    # ...
  end
end
```

constructor で `cart.open?` を判定してから transaction に入る形は double-submit で破綻する (両 thread が constructor チェックを通過する)。**lock! は transaction 内で**取り、ロック後に状態を再評価。

### `ActiveRecord::Deadlocked` を rescue

InnoDB の deadlock detection は二重課金を防いでくれるが、**caller には `ActiveRecord::Deadlocked` が伝搬する**。Controller で:

```ruby
rescue ActiveRecord::Deadlocked
  render json: { error: "concurrent_conflict", retryable: true }, status: :conflict
```

retry-able であることをクライアントに伝える (UX 上 500 にはしない)。

実例: `shopify/backend/components/orders/app/services/orders/checkout_service.rb` / `shopify/backend/components/orders/app/controllers/orders/storefront/{carts,checkouts}_controller.rb` / `shopify/backend/spec/multi_tenancy/scope_lint_spec.rb`。

---

## サブドメインで tenant 解決する middleware

Shopify 風の「`<shop>.example.com` で tenant を確定」運用では、Rails アプリの最前段に Rack middleware を置いて `current_shop` を rack env に積む:

```ruby
# components/core/lib/core/middleware/tenant_resolver.rb
SKIP_PATHS = %r{\A/(up|rails/|apps/api/)}  # health / 3rd-party API は素通り
def call(env)
  return @app.call(env) if env["PATH_INFO"]&.match?(SKIP_PATHS)
  subdomain = extract_subdomain(env)
  if subdomain
    shop = Core::Shop.find_by(subdomain: subdomain)
    return [404, ...] unless shop
    env["shopify.current_shop"] = shop
  end
  @app.call(env)
end
```

`ApplicationController#current_shop` は `request.env["shopify.current_shop"]` を読むだけ。

### 落とし穴: rodauth より前に挿入する

rodauth-rails の `before_create_account` フック内で `request.env["shopify.current_shop"]` を読むなら、**TenantResolver は Rodauth::Rails::Middleware より手前**に挿入する必要がある:

```ruby
config.after :load_config_initializers do |app|
  app.middleware.insert_before Rodauth::Rails::Middleware, Core::Middleware::TenantResolver
end
```

`config.middleware.use` だと末尾追加で順序が確定しない。`insert_before` を使う。

実例: `shopify/backend/components/core/lib/core/middleware/tenant_resolver.rb`。

---

## 認可: 2 層構造 (Resolver + Pundit Policy)

権限がドメインの中核（学習対象）であるプロジェクトでは、解決ロジックと verb 適用を分ける:

| 層 | 役割 | 例 |
| --- | --- | --- |
| `PermissionResolver` (PORO) | DB グラフから effective role を計算 | `effective_role` / `role_at_least?(:write)` |
| `Pundit::Policy` | verb (action) を role に束縛 | `RepositoryPolicy#merge_pull_request?` |
| Mutation / Resolver | `Pundit.policy(user, record).<verb>?` を呼ぶだけ | |

**アンチパターン**: mutation の中で `PermissionResolver` を直接呼んで `role_at_least?(:write)` で判断する。読み手が「policy はどこ？」となる。

`Scope#resolve` で index クエリを絞るときは、`outside_collaborator` のような **base 継承を持たない role** を見落としやすい。ロール一覧で「継承する役割だけ」を陽に書く:

```ruby
inheriting_roles = [Membership.roles[:member], Membership.roles[:admin]]
org_ids = Membership.where(user_id: user.id, role: inheriting_roles).pluck(:organization_id)
```

実例: `github/backend/app/services/permission_resolver.rb`, `github/backend/app/policies/repository_policy.rb`, `github/backend/spec/policies/repository_policy_scope_spec.rb`。

---

## GraphQL 採用プロジェクトでの追加規約

API スタイル全般は [api-style.md](../api-style.md#graphql-の運用github-プロジェクトで確立) を参照。Rails 視点で抑えておく点:

- `app/graphql/sources/` を切って `GraphQL::Dataloader::Source` 派生クラスを置く。Loader は viewer / repository などスコープ単位
- Mutation の base に `current_user!` / `authorize!` を置き、各 mutation は `authorize!(record, :verb?, strict: false)` で payload errors として返す
- Schema dump は `lib/tasks/graphql.rake` に書く (`BackendSchema.to_definition` を `docs/schema.graphql` に出す)。CI で `git diff --exit-code` を実行

---

## やらないこと

- 認証手段の網羅 / 監査ログ閲覧 UI / ロール作成 UI
- 余計な gem の追加（GraphQL / serializer / pundit etc. は学習目的で必要なら ADR を立てて入れる）
- defensive な error handling（内部呼び出しに `begin/rescue` を撒かない）
