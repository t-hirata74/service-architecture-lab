require "sequel/core"

# Phase 4-3 想定の最小認証 (ADR 0004)。rodauth-rails を JSON + JWT bearer モードで使う
# (perplexity / shopify / zoom / calendly と同形)。
# - POST /create-account → 同じ id で User 行も作る (shared PK)
# - POST /login → JWT を返す。以降は REST `Authorization: Bearer <token>` /
#   ActionCable は `?token=<jwt>` で同じ token を使う (ApplicationCable::Connection)。
# 本リポは「ローカル完結」「メール検証なし」方針なので verify_account 等のメール系は無効化する。
class RodauthMain < Rodauth::Rails::Auth
  configure do
    enable :create_account, :login, :logout, :json, :jwt, :change_password, :close_account

    # Initialize Sequel and have it reuse Active Record's database connection.
    db Sequel.mysql2(extensions: :activerecord_connection, keep_reference: false)
    convert_token_id_to_integer? { Account.columns_hash["id"].type == :integer }

    only_json? true
    require_password_confirmation? false
    require_login_confirmation? false

    rails_controller { RodauthController }

    account_status_column :status
    account_password_hash_column :password_hash

    login_param "email"
    password_minimum_length 8
    password_maximum_bytes 72

    # JWT secret は Rails secret_key_base (ActionCable Connection の検証と揃える)。
    jwt_secret { ENV.fetch("RODAUTH_JWT_SECRET", Rails.application.secret_key_base) }

    skip_status_checks? false

    # 新規登録時に display name を必須にし、User を shared PK で作成する。
    before_create_account do
      name = param_or_nil("name")
      throw_error_status(422, "name", "name required") if name.blank?
      @user_name = name
    end

    after_create_account do
      account_record = Account.find(account_id)
      account_record.update!(status: "verified") # メール検証スキップ (ローカル完結方針)
      User.create!(id: account_id, email: account[:email], name: @user_name)
    end

    # close_account で User も同 id で消す (has_one :user, dependent: :destroy 側でも担保)。
    after_close_account do
      User.find_by(id: account_id)&.destroy
    end
  end
end
