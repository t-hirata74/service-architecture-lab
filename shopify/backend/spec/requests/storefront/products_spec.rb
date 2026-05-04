require "rails_helper"

RSpec.describe "GET /storefront/products", type: :request do
  let!(:acme) { Core::Shop.create!(subdomain: "acme", name: "ACME") }
  let!(:globex) { Core::Shop.create!(subdomain: "globex", name: "Globex") }

  before do
    Catalog::Product.create!(shop: acme, slug: "tee", title: "Tee (acme)", status: :active)
    Catalog::Product.create!(shop: acme, slug: "draft", title: "Draft", status: :draft)
    Catalog::Product.create!(shop: globex, slug: "tee", title: "Tee (globex)", status: :active)
  end

  it "current_shop の active な product のみ返す" do
    get "/storefront/products", headers: { "X-Shop-Subdomain" => "acme" }
    expect(response).to have_http_status(:ok)
    titles = response.parsed_body.map { |p| p["title"] }
    expect(titles).to contain_exactly("Tee (acme)")
  end

  it "別 shop からは別の product が見える (cross-tenant isolation)" do
    get "/storefront/products", headers: { "X-Shop-Subdomain" => "globex" }
    expect(response.parsed_body.map { |p| p["title"] }).to contain_exactly("Tee (globex)")
  end

  it "未解決 subdomain は 404" do
    get "/storefront/products", headers: { "X-Shop-Subdomain" => "ghost" }
    expect(response).to have_http_status(:not_found)
  end
end
