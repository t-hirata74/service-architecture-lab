require "sequel/core"

# Phase 4-3: rodauth-rails を JSON + JWT bearer モードで使う (zoom / shopify / perplexity と同形)。
# - POST /create-account → Host row も同じ id で作成
# - POST /login → JWT を返す。以降は `Authorization: Bearer <token>`
# 本リポは「ローカル完結」「メール検証なし」方針なので、verify_account 等のメール系は無効化する。
class RodauthMain < Rodauth::Rails::Auth
  configure do
    enable :create_account, :login, :logout, :json, :jwt, :change_password, :close_account

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

    skip_status_checks? false

    jwt_secret { ENV.fetch("RODAUTH_JWT_SECRET", Rails.application.secret_key_base) }

    # Phase 4-3: 新規登録時に host_name と default_tz_id を必須にし、Host を shared PK で作成する。
    before_create_account do
      name = param_or_nil("name")
      tz_id = param_or_nil("default_tz_id") || "UTC"
      throw_error_status(422, "name", "name required") if name.blank?
      @host_name = name
      @host_tz_id = tz_id
    end

    after_create_account do
      account_record = Account.find(account_id)
      account_record.update!(status: "verified")  # メール検証スキップ (ローカル完結方針)
      Host.create!(id: account_id, email: account[:email],
                   name: @host_name, default_tz_id: @host_tz_id)
    end

    # Account closure: Host も同 id で削除される (has_one :host, dependent: :destroy)。
  end
end
