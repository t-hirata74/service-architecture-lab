# request spec 用: rodauth-rails JWT 経由で User を作成し JWT ヘッダを取り出す
# (perplexity / shopify / zoom / calendly と同形)。
module AuthHelpers
  def json_headers
    { "Content-Type" => "application/json", "Accept" => "application/json" }
  end

  def auth_headers(token)
    json_headers.merge("Authorization" => token)
  end

  def signup(email:, password: "supersecret123", name: "Test User")
    post "/create-account",
         params: { email:, password:, name: }.to_json,
         headers: json_headers
    raise "signup failed: #{response.body}" unless response.successful?

    token = response.headers["Authorization"]
    raise "no JWT in Authorization header" if token.blank?

    [ User.find_by!(email:), auth_headers(token) ]
  end
end

RSpec.configure do |c|
  c.include AuthHelpers, type: :request
end
