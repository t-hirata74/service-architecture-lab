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
- テスト: minitest + fixtures（Rails 標準のまま）

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
- 例: `AiWorkerClient` は Python (FastAPI) の `/summarize` を呼ぶラッパー。URL は `ENV.fetch("AI_WORKER_URL", "http://localhost:8000")`

---

## Migration / Schema

- migration ファイル名は `YYYYMMDDHHmmss_create_xxx.rb`（Rails 標準）
- `db/schema.rb` をコミット
- 不可逆な migration（データ移行など）は `up` / `down` を両方書く

---

## やらないこと

- 認証手段の網羅 / 監査ログ閲覧 UI / ロール作成 UI
- 余計な gem の追加（GraphQL / serializer / pundit etc. は学習目的で必要なら ADR を立てて入れる）
- defensive な error handling（内部呼び出しに `begin/rescue` を撒かない）
