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

実例: `github/backend/app/services/issue_number_allocator.rb`, `github/backend/spec/services/issue_number_allocator_spec.rb`。

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
