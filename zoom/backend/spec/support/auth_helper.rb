# 認証付き request spec のためのヘルパ。
# rodauth の本番経路 (POST /create-account → POST /login) を経由して JWT を取得する。
module AuthHelper
  def create_authenticated_user(email: nil, display_name: nil, password: "password123")
    email ||= "user-#{SecureRandom.hex(4)}@example.test"
    display_name ||= "User #{SecureRandom.hex(2)}"

    post "/create-account",
         params: { email:, password:, display_name: },
         as: :json
    raise "create-account failed: #{response.status} #{response.body}" unless response.status.in?([200, 201])

    user = User.find_by!(email: email)

    post "/login", params: { email:, password: }, as: :json
    raise "login failed: #{response.status}" unless response.status == 200

    token = response.headers["Authorization"]
    [user, { "Authorization" => "Bearer #{token}" }]
  end

  def jwt_headers_for(account_id)
    payload = { "account_id" => account_id, "authenticated_by" => ["password"] }
    secret = ENV.fetch("RODAUTH_JWT_SECRET", Rails.application.secret_key_base)
    token = JWT.encode(payload, secret, "HS256")
    { "Authorization" => "Bearer #{token}" }
  end
end

RSpec.configure do |config|
  config.include AuthHelper, type: :request
end
