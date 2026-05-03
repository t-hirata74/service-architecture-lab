require "rails_helper"

# ADR 0007: rodauth-rails JWT bearer の最小フロー e2e.
# - POST /create-account でアカウント + User が共有 PK で作成される
# - POST /login で JWT を返し、Authorization: Bearer で /queries にアクセスできる
# - JWT 無し / 不正な JWT は 401 (X-User-Id フォールバックは別 spec で確認)
RSpec.describe "rodauth-rails JWT bearer", type: :request do
  let(:email)    { "alice@example.com" }
  let(:password) { "correct horse battery staple" }

  def parsed
    JSON.parse(response.body)
  end

  def login_and_jwt
    post "/login", params: { email: email, password: password }.to_json,
                   headers: { "Content-Type" => "application/json", "Accept" => "application/json" }
    expect(response).to have_http_status(:ok)
    response.headers["Authorization"]
  end

  before do
    post "/create-account", params: { email: email, password: password }.to_json,
                            headers: { "Content-Type" => "application/json", "Accept" => "application/json" }
    expect(response).to have_http_status(:ok).or have_http_status(:created)
  end

  it "create-account で User が account_id と同じ id で作られる" do
    account = Account.find_by(email: email)
    expect(account).to be_present
    user = User.find_by(id: account.id)
    expect(user).to be_present
    expect(user.email).to eq(email)
  end

  it "login → JWT → Authorization: Bearer で /queries にアクセスできる" do
    jwt = login_and_jwt
    expect(jwt).to be_present

    post "/queries", params: { text: "test" }.to_json,
                     headers: {
                       "Content-Type" => "application/json",
                       "Authorization" => jwt
                     }
    expect(response).to have_http_status(:created)
    expect(parsed["status"]).to eq("pending")
  end

  it "JWT 無し + X-User-Id 無しは 401" do
    post "/queries", params: { text: "test" }.to_json,
                     headers: { "Content-Type" => "application/json" }
    expect(response).to have_http_status(:unauthorized)
  end

  it "Authorization: Bearer に不正な JWT を渡すと拒否される" do
    post "/queries", params: { text: "test" }.to_json,
                     headers: {
                       "Content-Type" => "application/json",
                       "Authorization" => "Bearer not-a-real-jwt"
                     }
    # rodauth-jwt は decode 失敗時に 400 (malformed) を返す.
    # frontend 視点では 4xx のいずれかであれば再 login を促す処理に入れる.
    expect(response.status).to be_between(400, 401).inclusive
  end
end
