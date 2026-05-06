require "sequel/core"

# Phase 4-3: rodauth-rails を JSON + JWT bearer モードで使う (shopify / perplexity と同形)。
# - POST /create-account → User row も同じ id で作成
# - POST /login → JWT を返す。以降は `Authorization: Bearer <token>`
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

    # 検証メールはローカル完結方針のためスキップ。新規登録 = 即 verified 扱い。
    skip_status_checks? false

    jwt_secret { ENV.fetch("RODAUTH_JWT_SECRET", Rails.application.secret_key_base) }

    before_create_account do
      display_name = param_or_nil("display_name")
      throw_error_status(422, "display_name", "display_name required") if display_name.blank?
      @display_name_for_user = display_name
    end

    after_create_account do
      account_record = Account.find(account_id)
      account_record.update!(status: "verified") # ローカル完結方針: メール検証はスキップ
      User.create!(id: account_id, email: account[:email], display_name: @display_name_for_user)
    end
  end
end
