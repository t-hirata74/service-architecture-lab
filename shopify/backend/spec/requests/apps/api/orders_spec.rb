require "rails_helper"

# Review fix I5: 3rd-party App API。
# - Bearer token (api_token) → AppInstallation 解決 → installation.shop が current_shop
# - read_orders scope が必要
RSpec.describe "GET /apps/api/orders", type: :request do
  let!(:shop) { Core::Shop.create!(subdomain: "acme", name: "ACME") }
  let!(:other_shop) { Core::Shop.create!(subdomain: "globex", name: "Globex") }
  let!(:platform_app) { Apps::App.create!(name: "shipping-app", secret: "supersecret-1234567890") }
  let(:raw_token) { SecureRandom.hex(16) }
  let!(:install) do
    Apps::AppInstallation.create!(
      shop: shop, app: platform_app, scopes: "read_orders",
      api_token_digest: Apps::AppInstallation.digest_token(raw_token)
    )
  end
  let!(:noscope_install) do
    Apps::AppInstallation.create!(
      shop: other_shop, app: platform_app, scopes: "",
      api_token_digest: Apps::AppInstallation.digest_token("noscope-token")
    )
  end

  before do
    customer = Core::User.create!(shop: shop, email: "buyer@example.com")
    Orders::Order.create!(shop: shop, customer: customer, number: 1, status: :paid, total_cents: 1000, currency: "JPY")
    other_customer = Core::User.create!(shop: other_shop, email: "x@y.z")
    Orders::Order.create!(shop: other_shop, customer: other_customer, number: 1, status: :paid, total_cents: 9999, currency: "JPY")
  end

  it "Bearer 無しは 401" do
    get "/apps/api/orders"
    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body["error"]).to eq("invalid_app_token")
  end

  it "不正な Bearer は 401" do
    get "/apps/api/orders", headers: { "Authorization" => "Bearer wrong" }
    expect(response).to have_http_status(:unauthorized)
  end

  it "read_orders scope が無いと 403" do
    get "/apps/api/orders", headers: { "Authorization" => "Bearer noscope-token" }
    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body["scope"]).to eq("read_orders")
  end

  it "正規の token は installation.shop の Order だけ返す (cross-tenant 漏れ無し)" do
    get "/apps/api/orders", headers: { "Authorization" => "Bearer #{raw_token}" }
    expect(response).to have_http_status(:ok)
    titles = response.parsed_body.map { |o| o["total_cents"] }
    expect(titles).to contain_exactly(1000)  # other_shop (9999) は含まれない
  end

  it "subdomain 無しでも (Apps API は SKIP_PATHS) 401 にならず token 認証だけ走る" do
    # `/apps/api/*` は TenantResolver の SKIP_PATHS なので、subdomain 無し host でも到達できる
    get "/apps/api/orders", headers: { "Authorization" => "Bearer #{raw_token}", "Host" => "localhost" }
    expect(response).to have_http_status(:ok)
  end
end
