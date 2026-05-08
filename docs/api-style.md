# API スタイル方針 (REST / GraphQL の選定)

各プロジェクトの **主要技術課題** に応じて REST / GraphQL を選ぶ。
リポジトリ全体で 1 つのスタイルに固定せず、**判断軸とトレードオフを学習成果として残す**。

---

## 判断軸

| 観点 | REST が向く | GraphQL が向く |
| --- | --- | --- |
| データ構造 | リソースが独立し、固定形のレスポンスで足りる | リソースの**関係グラフ**を辿り、画面ごとに必要な field が違う |
| 主要操作 | CRUD + state transition (action) | 任意のサブセット投影 / nested 取得 |
| キャッシュ | HTTP / CDN レイヤーで効かせやすい | クエリ単位の永続化キャッシュで自前管理 |
| 認可 | エンドポイント単位でリソース ABAC | フィールド単位の認可が必要（複雑化） |
| 学習コスト | 低い (Rails 標準 / OpenAPI) | 高い (graphql-ruby + dataloader + N+1 + auth) |
| 向いている技術課題 | 状態機械 / アップロード / 通知配信 / 既読同期 | 権限グラフ / Issue リレーション / 連結クエリ |

> 共通: **リアルタイム配信は WebSocket / SSE が主役**で、REST と GraphQL のどちらを選んでも直交する。

---

## プロジェクト別の選定

| プロジェクト | スタイル | 採用理由 |
| --- | --- | --- |
| `slack`   | **REST + OpenAPI** | 主要技術課題（fan-out / 既読 cursor）は WebSocket と直交。残りの CRUD は固定形で OpenAPI と相性が良い |
| `youtube` | **REST + OpenAPI** | アップロード状態機械は action ベースの REST が素直。Recommendation / 検索 / コメントも独立リソースで GraphQL に倒す価値が薄い |
| `github` | **GraphQL** (graphql-ruby + urql) | 主要技術課題が「**Issue / PR / Review / Permission の関係グラフ**」。REST だと endpoint 爆発 + N+1 議論が分散する。実 GitHub も v4 が GraphQL |
| `perplexity` | **REST + SSE** (`ActionController::Live`) | 同期 API は固定形で十分、stream 部分のみ SSE で切り出す |
| `instagram` | **REST** (DRF) | フォロー / タイムラインは action ベースの REST で十分。スキーマ定義は DRF Serializer ベース |
| `discord` | **REST + WebSocket** (`/gateway`) | gateway protocol が主役、REST は補助 |
| `reddit` | **REST + JSON** (FastAPI) | サブレディット / post / comment / vote は典型的な CRUD + custom action。FastAPI 型駆動で OpenAPI 自動生成。GraphQL を入れる動機が薄い (関係グラフは comment tree だけで、それは path 列で十分扱える) |

### 選定をしない・先送りでよいケース

- **`discord` / `figma` / `zoom`**: WebRTC / CRDT が主役で、REST/GraphQL の比重が小さい。プロジェクト着手時に再検討
- **`stripe` / `shopify`**: 実プロダクトが REST 寄り。学習価値は REST 側で取りに行く
- **AI 系（chatgpt / coding-agent）**: HTTP 部分は薄い。SSE / Streaming が主役

---

## REST + OpenAPI の運用

### 採用ツール

- **`committee-rails`** — Rails の request spec で **レスポンスを OpenAPI スキーマに照合**する。スキーマと実装が乖離した瞬間にテストが落ちる
- **`openapi-typescript`** — Frontend が `openapi.yml` から TS 型を **自動生成**。`lib/api.ts` で手書きしていた型は廃止
- **`openapi-fetch`** — 上記の型を使った薄い `fetch` ラッパ（任意）

### 配置

```text
<service>/backend/docs/openapi.yml      # 単一スキーマファイル (手書き)
<service>/frontend/src/lib/api-types.ts # openapi-typescript で自動生成
```

### 規約

- **エンドポイントを実装する前に openapi.yml を書く**（schema-first）
- **request spec が openapi.yml を必ず通す**（`assert_response_schema_confirm` 等）
- **frontend は `npm run gen:api` で型再生成**。`tsc --noEmit` で乖離を検知
- **レスポンスは objects ではなく `{ items: [...] }` ラップ**を基本（ページネーション拡張余地）

### ステータスコードの規約

- `200` 成功 / `201` create / `202` async accepted
- `400` クライアントの形不正 (parameter missing 等)
- `404` リソース不在 / **状態的に隠したい（viewable でない）** 場合も 404
- `409` state conflict（例: `publish!` を非 ready から呼ぶ）
- `422` validation error（`{ errors: ["..."] }`）
- 外部依存失敗時は **`200` + `degraded: true`**（[graceful degradation](operating-patterns.md#graceful-degradation)）

---

## GraphQL の運用（github プロジェクトで確立）

github プロジェクト (ADR 0001) で実運用に入った構成。次に GraphQL を選ぶプロジェクトはここから始める。

### 採用ツール

- **`graphql-ruby` ~> 2.4** — schema-first ではなく **コード定義を SDL にダンプ** (rake task で `<service>/backend/docs/schema.graphql` に書き出し)
- **`GraphQL::Dataloader`** — N+1 対策。`graphql-batch` も併用可だが、新規プロジェクトは Dataloader を推奨
- **`pundit`** — 認可は **policy verb 単位**で書き、mutation / field resolver から `Pundit.policy(user, record).<verb>?` で呼ぶ
- **`urql` (frontend)** — `@graphql-codegen/cli` + `typescript-urql` で型付き hooks 生成（`gen:api` script）

### 配置

```text
<service>/backend/app/graphql/
  <service>_schema.rb                      # query / mutation / dataloader 設定
  types/                                   # *_type.rb / *_enum.rb
  mutations/base_mutation.rb               # current_user! / authorize! ヘルパ
  mutations/<action>.rb                    # createIssue, mergePullRequest など action 単位
  sources/                                 # GraphQL::Dataloader::Source 派生クラス
<service>/backend/lib/tasks/graphql.rake   # rake graphql:dump_schema
<service>/backend/docs/schema.graphql      # 自動エクスポート (CI で diff チェック)
<service>/frontend/codegen.ts              # graphql-codegen 設定
<service>/frontend/lib/gql/types.ts        # 自動生成 (commit してCI で diff チェック)
```

### 規約

- **Mutation は action 単位**: `createIssue`, `assignReviewer`, `mergePullRequest`。CRUD 汎用 `updateIssue` は作らない
- **認可は Policy 経由に統一**: mutation 内で `PermissionResolver` を直接呼ばない。RepositoryPolicy 等に `merge_pull_request?` のような verb を生やし、`authorize!(record, :merge_pull_request?, strict: false)` で payload errors として返す
- **Field 単位認可で `null` を返す**: 権限不足のリソースは GraphQL 上 `null` (HTTP は 200)。エラーは raise しない
- **`/graphql` は GET と POST の両方を受ける**: `urql` は queries に GET を使う (HTTP cache の活用)。Rails 側 `match "/graphql", via: %i[get post]`、CORS にも `methods: %i[get post options]`
- **Schema dump は CI で diff チェック**: `rake graphql:dump_schema` + `git diff --exit-code docs/schema.graphql`。OpenAPI の `committee-rails` に相当する乖離検知
- **Enum 命名衝突は許容してマップする**: 例えば `state: merged` と `mergeable_state: merged` は Rails enum 側で衝突するので Ruby 側は `merged_state` にし、GraphQL 側 (`graphql_name`) で `MERGED` に再マップする

### N+1 対策

- ADR が graphql-batch / Dataloader を掲げたら **`spec/graphql/n_plus_one_spec.rb` で計測する**: `ActiveSupport::Notifications.subscribed("sql.active_record")` でクエリを数え、件数 N に対してクエリが線形に増えないことを assert
- 例: `Sources::ViewerPermissionSource` 1 つで membership / team / collaborator を全 repo 横断で 1 度に取る (github)

### Frontend (urql + Next.js App Router)

詳細は [coding-rules/frontend.md](coding-rules/frontend.md#urql-provider-pattern) を参照。重要な点だけ：

- **Provider は Client Component**。`useState(() => createClient())` で 1 度だけ生成（モジュール singleton はマルチリクエスト SSR で危険）
- **`fetchOptions` は closure**: localStorage や cookie からの auth header 注入は fetch 時に毎回読み直す
- **codegen 出力は commit する**: `lib/gql/types.ts` を CI で diff チェック (schema dump と同じ思想)

### サンプルコード位置

- backend: `github/backend/app/graphql/` 一式
- frontend: `github/frontend/components/UrqlProvider.tsx`, `github/frontend/codegen.ts`
- N+1 spec: `github/backend/spec/graphql/n_plus_one_spec.rb`

---

## マルチテナント API: subdomain による tenant 解決 (shopify)

shopify で確立。複数 SaaS tenant を同一 backend で運用する際の API 入口設計。

### 規律 1: tenant は middleware で解決し、controller は `current_shop` を読むだけ

```ruby
# components/core/lib/core/middleware/tenant_resolver.rb
def call(env)
  return @app.call(env) if env["PATH_INFO"]&.match?(SKIP_PATHS)
  if subdomain = extract_subdomain(env)
    shop = Core::Shop.find_by(subdomain: subdomain)
    return [404, ...] unless shop
    env["shopify.current_shop"] = shop
  end
  @app.call(env)
end
```

`ApplicationController#current_shop` は `request.env["shopify.current_shop"]` を読むだけ。controller / service には「subdomain 解析」のロジックを漏らさない。

### 規律 2: SKIP_PATHS で **subdomain を要求しない経路** を明示

| 経路 | 理由 |
| --- | --- |
| `/up`, `/rails/*` | health check |
| `/apps/api/*` (3rd-party API) | Bearer token から AppInstallation 経由で shop 解決 |
| `/create-account`, `/login` 等 (rodauth) | 登録時に shop が決まるので **subdomain 必須** (skip しない) |

「subdomain なしで叩ける経路」を明示的に管理することで、tenant 漏れの事故 (subdomain 無しでも某 endpoint が動いてしまう) を防ぐ。

### 規律 3: middleware は Rodauth より**前**に挿入

rodauth-rails は middleware として動作する。`before_create_account` フックで `request.env["shopify.current_shop"]` を読みたい場合、TenantResolver は Rodauth より前に挿入する必要がある:

```ruby
config.after :load_config_initializers do |app|
  app.middleware.insert_before Rodauth::Rails::Middleware, Core::Middleware::TenantResolver
end
```

`config.middleware.use` だと末尾追加で順序が確定しない。**`insert_before` を使う**。

実例: `shopify/backend/components/core/lib/core/middleware/tenant_resolver.rb` + `shopify/backend/spec/middleware/tenant_resolver_spec.rb`。

---

## 3rd-party App API: Bearer token + scope 認可 (shopify)

shopify で確立。「プラットフォームに install された app が tenant のリソースを叩く API」の設計。

### 規律 1: Bearer token は SHA256 digest で永続化、生 token は install 時のみ返す

```ruby
class AppInstallation < ApplicationRecord
  def self.digest_token(token) = Digest::SHA256.hexdigest(token)
end
```

DB に平文を持たない。verify は受信した Bearer の digest で `find_by(api_token_digest: ...)`。生 token は install 直後に 1 回だけクライアントに返し、再発行不可 (失くしたら作り直し)。

### 規律 2: tenant は `installation.shop` から解決 (subdomain 不要)

3rd-party App API は subdomain を持たない (アプリ側はテナントを意識しない)。`Apps::Api::BaseController#current_shop` を `installation.shop` で override し、TenantResolver の SKIP_PATHS に `/apps/api/` を入れて素通りさせる:

```ruby
class Apps::Api::BaseController < ApplicationController
  before_action :authenticate_app_installation!
  def current_shop
    current_app_installation.shop  # subdomain ではなく Bearer 由来
  end
end
```

### 規律 3: scope は per-action で `requires_scope!` を呼ぶ

`AppInstallation#scopes` は `,` 区切りの文字列 (例: `"read_orders,write_inventory"`)。各 controller action の最初で:

```ruby
class Apps::Api::OrdersController < BaseController
  def index
    requires_scope!("read_orders")
    # ...
  end
end
```

scope 不足は **403 Forbidden** + `{ error: "missing_scope", scope: "read_orders" }`。401 (token 無効) と区別する。

### 規律 4: エラー型を 3 つに分ける

| status | 意味 |
| --- | --- |
| 401 invalid_app_token | Bearer 無し / token がいかなる installation にも一致しない |
| 403 missing_scope | token は valid だが必要な scope を持たない |
| 404 (該当 controller の standard) | リソース不在 (cross-tenant 含む — installation.shop に紐づかないリソース) |

実例: `shopify/backend/components/apps/app/controllers/apps/api/{base,orders}_controller.rb` + `shopify/backend/spec/requests/apps/api/orders_spec.rb`。

---

## 自社プロダクト認証: rodauth-rails JWT bearer + shared PK (perplexity / shopify / zoom / calendly で 4 連続採用)

slack ADR 0004 で初導入後、**perplexity / shopify / zoom / calendly が同形を踏襲**して安定化したパターン。4 サービス × 各 ADR で十分検証された自社向け認証方式として共通化する。

### 規律 1: JWT のみ enable / cookie や session は使わない

```ruby
# app/misc/rodauth_main.rb
class RodauthMain < Rodauth::Rails::Auth
  configure do
    enable :create_account, :login, :logout, :json, :jwt, :change_password, :close_account

    only_json? true
    require_password_confirmation? false
    require_login_confirmation? false

    login_param "email"
    password_minimum_length 8
    password_maximum_bytes 72

    jwt_secret { ENV.fetch("RODAUTH_JWT_SECRET", Rails.application.secret_key_base) }
  end
end
```

- `:remember` (cookie 系) は JSON-only / SPA 構成と相性が悪いので **enable しない**。生成時に `app/misc/rodauth_app.rb` の `r.load_memory` も削除する
- `only_json? true` で view を持たず、エラーは JSON 200 + body 内 `{"field-error": ...}` で返る (rodauth の挙動)
- パスワードは min 8 / max 72 bytes (OWASP 準拠)
- production env では `RODAUTH_JWT_SECRET` 未設定時に boot raise する規律 (calendly review fix I-B-2)。Rails master key へのフォールバックは dev/test のみ許容

### 規律 2: `accounts` (rodauth) と ドメイン model (User / Host / Shop) は **shared PK で 1:1**

```ruby
# rodauth_main.rb
before_create_account do
  display_name = param_or_nil("display_name")
  throw_error_status(422, "display_name", "display_name required") if display_name.blank?
  @display_name_for_user = display_name
end

after_create_account do
  account_record = Account.find(account_id)
  account_record.update!(status: "verified")  # メール検証スキップ (ローカル完結方針)
  User.create!(id: account_id, email: account[:email], display_name: @display_name_for_user)
end
```

- `accounts.id == users.id` で関連付け (zoom: User / shopify: Shop / calendly: Host も同形)
- model 側は `belongs_to :account, foreign_key: :id, primary_key: :id, optional: true`
- メール検証 (`verify_account` feature) は **本リポでは無効化**: ローカル完結方針 + 学習目的では SMTP 不要

### 規律 3: ApplicationController の `current_*` は **rodauth.session_value** から引く

```ruby
# app/controllers/application_controller.rb
class ApplicationController < ActionController::API
  include Pundit::Authorization

  class Unauthorized < StandardError; end
  rescue_from Unauthorized do
    render json: { error: "unauthorized" }, status: :unauthorized
  end

  def current_user
    @current_user ||= find_current_user!
  end
  alias_method :authenticate_user!, :current_user  # before_action :authenticate_user! 用

  private

  def find_current_user!
    account_id = rodauth.session_value
    raise Unauthorized, "invalid or expired JWT" if account_id.nil?
    User.find_by(id: account_id) || raise(Unauthorized, "user not provisioned")
  end
end
```

- `rodauth.session_value` が JWT 検証 + account_id 取得を担う
- Pundit の `current_user` 規約に合わせて alias 公開 (calendly では `current_host` を主役にして `current_user` を alias)

### 規律 4: ドメイン model の email 変更は Account 側にも同期 (calendly review fix I-C-1)

`accounts.email` UNIQUE と `<domain_model>.email` UNIQUE が並列で存在する設計のため、**ドメイン model 側で email を update した時に drift する** リスクがある:

```ruby
# app/models/host.rb (or User.rb)
after_save :sync_email_to_account, if: :saved_change_to_email?

private

def sync_email_to_account
  return unless account
  account.update_columns(email: email) unless account.email == email
end
```

- `update_columns` で validation/callback をスキップ (account の他の callback を起こさない)
- 逆方向 (Account 側から email を変更する) はそもそも rodauth の `change_login` 経由で行われるはず — そこに到達するなら別途 sync が必要

### 規律 5: frontend は `Authorization` レスポンスヘッダから JWT を取り出して localStorage 保持

```typescript
// frontend/src/lib/api.ts
export async function login(email: string, password: string): Promise<string> {
  const res = await fetch(`${API_BASE}/login`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Accept: "application/json" },
    body: JSON.stringify({ email, password }),
  });
  if (!res.ok) throw new Error(`login failed (${res.status})`);
  const token = res.headers.get("Authorization");  // rodauth-jwt が素の JWT を返す
  if (!token) throw new Error("no Authorization header");
  setToken(token);
  return token;
}
```

- rodauth-jwt は `Authorization: <token>` (Bearer 接頭辞なし) で返すので、そのまま `localStorage.setItem(...)` し、次回リクエストで `Authorization: Bearer <token>` として送る
- backend 側の CORS は `expose: %w[Authorization]` を必ず付ける (これを忘れると frontend がヘッダを読めない)

### 規律 6: signup も同じ Authorization ヘッダ経由で auto-login する

```typescript
export async function signup(email: string, password: string, name: string): Promise<string> {
  const res = await fetch(`${API_BASE}/create-account`, { ... });
  const token = res.headers.get("Authorization");  // signup → そのままログイン状態に
  setToken(token);
  return token;
}
```

これで「signup → そのままダッシュボードへ遷移」が 1 リクエストで成立する (UX 改善)。

### 4 サービスでの差分 (テンプレを使い回せる範囲)

| サービス | ドメイン model | 必須カスタム param |
| --- | --- | --- |
| `perplexity` | User | display_name |
| `shopify` | Shop (multi-tenant) | shop_name + subdomain |
| `zoom` | User | display_name |
| `calendly` | Host | name + default_tz_id |

`before_create_account` で必須 param を `throw_error_status(422, ...)`、`after_create_account` で domain model を shared PK で `create!` するパターンが完全に揃う。**新規 Rails プロジェクトはこの 6 規律を起点にコピーで開始可能**。

詳細実装: perplexity ADR 0007 / shopify ADR 0004 (Apps API も同形 Bearer) / zoom Phase 4-3 / calendly Phase 4-3。

---

## 現時点の宿題

- `slack/backend` と `youtube/backend` の OpenAPI 契約検証は導入済み (e94df38)
- ADR は **プロジェクト単位で 1 本** 起こす方針 (slack 0006, youtube 0007 = REST + OpenAPI、github 0001 = GraphQL)

---

## 関連ドキュメント

- [coding-rules/rails.md](coding-rules/rails.md) — Service オブジェクトと ai-worker 境界の共通方針
- [testing-strategy.md](testing-strategy.md) — request spec から OpenAPI を検証
- [operating-patterns.md](operating-patterns.md) — graceful degradation とエラーハンドリング規約
