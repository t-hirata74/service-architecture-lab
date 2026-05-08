# Phase 4 request spec helper: rodauth-rails JWT 経由で host を作成 + JWT ヘッダを取り出す。
# perplexity / shopify / zoom と同形のヘルパ。
module AuthHelpers
  def signup_and_login(email:, password: "supersecret123", name: "Test Host", tz: "Asia/Tokyo")
    post "/create-account",
         params: { email: email, password: password, name: name, default_tz_id: tz }.to_json,
         headers: { "Content-Type" => "application/json", "Accept" => "application/json" }
    raise "signup failed: #{response.body}" unless response.successful?

    token = response.headers["Authorization"]
    raise "no JWT in Authorization header" if token.blank?
    host = Host.find_by!(email: email)
    [ host, { "Authorization" => token, "Accept" => "application/json", "Content-Type" => "application/json" } ]
  end
end

RSpec.configure do |c|
  c.include AuthHelpers, type: :request
end
