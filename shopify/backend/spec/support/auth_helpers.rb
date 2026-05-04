module AuthHelpers
  # rodauth の create-account で account+User を作り、login で JWT を取得して返す。
  def register_and_login(subdomain:, email:, password: "passw0rd")
    headers = {
      "Content-Type" => "application/json",
      "Accept" => "application/json",
      "X-Shop-Subdomain" => subdomain
    }
    post "/create-account", params: { email: email, password: password }.to_json, headers: headers
    raise "create-account failed: #{response.body}" unless [ 200, 201 ].include?(response.status)

    post "/login", params: { email: email, password: password }.to_json, headers: headers
    raise "login failed: #{response.body}" unless response.status == 200

    response.headers["Authorization"]
  end

  def auth_headers(subdomain:, jwt:)
    {
      "X-Shop-Subdomain" => subdomain,
      "Authorization" => jwt,
      "Content-Type" => "application/json",
      "Accept" => "application/json"
    }
  end
end

RSpec.configure do |config|
  config.include AuthHelpers, type: :request
end
