require "sequel/core"

# ADR 0007 (perplexity と同形): rodauth-rails を JSON + JWT bearer モードで使う。
# - login → JWT を返す / 以降は `Authorization: Bearer <token>`
# - account 作成と同時に Core::User を同じ id で作成し、shop_id を bind する
class RodauthMain < Rodauth::Rails::Auth
  configure do
    enable :create_account,
      :login, :logout,
      :json, :jwt,
      :change_password,
      :close_account

    db Sequel.mysql2(extensions: :activerecord_connection, keep_reference: false)
    convert_token_id_to_integer? { Core::Account.columns_hash["id"].type == :integer }

    only_json? true
    require_password_confirmation? false
    require_login_confirmation? false

    rails_controller { RodauthController }

    account_status_column :status
    account_password_hash_column :password_hash

    login_param "email"

    password_minimum_length 8
    password_maximum_bytes 72

    jwt_secret { ENV.fetch("RODAUTH_JWT_SECRET", Rails.application.secret_key_base) }

    # 登録時に shop_id を確定する。テナント解決済みの shop が無いと create_account を弾く。
    # `current_shop` は middleware が rack env に積んでいる (TenantResolver)。
    before_create_account do
      shop = request.env["shopify.current_shop"]
      throw_error_status(403, "shop", "tenant unresolved") unless shop
      @shop_id_for_user = shop.id
    end

    after_create_account do
      Core::User.create!(id: account_id, email: account[:email], shop_id: @shop_id_for_user)
    end
  end
end
