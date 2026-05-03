require "sequel/core"

# ADR 0007: rodauth-rails を JSON + JWT bearer モードで使う.
# - login → JWT を返す
# - 以降は Authorization: Bearer <token> で認証
# - cookie auth (:remember) は採用しない (cross-origin frontend + SSE で扱いやすい JWT を採用)
class RodauthMain < Rodauth::Rails::Auth
  configure do
    enable :create_account,
      :login, :logout,
      :json, :jwt,
      :change_password,
      :close_account

    db Sequel.mysql2(extensions: :activerecord_connection, keep_reference: false)
    convert_token_id_to_integer? { Account.columns_hash["id"].type == :integer }

    only_json? true
    require_password_confirmation? false
    require_login_confirmation? false

    rails_controller { RodauthController }
    title_instance_variable :@page_title

    account_status_column :status
    account_password_hash_column :password_hash

    login_param "email"

    send_email do |email|
      db.after_commit { email.deliver_later }
    end

    password_minimum_length 8
    password_maximum_bytes 72

    # JWT secret: ENV → Rails.application.secret_key_base の順でフォールバック.
    # 本番では Secrets Manager から RODAUTH_JWT_SECRET を ECS task に注入 (infra/terraform/secrets.tf).
    jwt_secret { ENV.fetch("RODAUTH_JWT_SECRET", Rails.application.secret_key_base) }

    # アカウント作成と同時に同じ id で User レコードを作る (ADR 0007 共有 PK).
    after_create_account do
      User.create!(id: account_id, email: account[:email])
    end
  end
end
