require "rails_helper"

# Phase 4 の API 統合: register → cart 操作 → checkout のフルフロー。
# ADR 0003: 在庫不足時に 409 Conflict を返し、Order は作られないことを HTTP レイヤから確認する。
RSpec.describe "Storefront cart + checkout", type: :request do
  let!(:shop) { Core::Shop.create!(subdomain: "acme", name: "ACME") }
  let!(:product) { Catalog::Product.create!(shop: shop, slug: "tee", title: "Tee", status: :active) }
  let!(:variant) { Catalog::Variant.create!(shop: shop, product: product, sku: "TEE-S", price_cents: 1000, currency: "JPY") }
  let!(:location) { Inventory::Location.create!(shop: shop, name: "main", kind: "warehouse") }

  before do
    Inventory::InventoryLevel.create!(shop: shop, variant: variant, location: location, on_hand: 3)
  end

  let(:subdomain) { "acme" }
  let(:jwt) { register_and_login(subdomain: subdomain, email: "buyer@example.com") }

  it "cart に追加 → checkout で Order 確定 + 在庫減算" do
    headers = auth_headers(subdomain: subdomain, jwt: jwt)

    post "/storefront/cart/items", params: { variant_id: variant.id, quantity: 2 }.to_json, headers: headers
    expect(response).to have_http_status(:created)
    expect(response.parsed_body["items"].first).to include("quantity" => 2, "sku" => "TEE-S")

    post "/storefront/checkout", params: {}.to_json, headers: headers
    expect(response).to have_http_status(:created)
    expect(response.parsed_body["number"]).to eq(1)
    expect(response.parsed_body["total_cents"]).to eq(2000)

    expect(Inventory::InventoryLevel.find_by(variant: variant, location: location).on_hand).to eq(1)
  end

  it "在庫不足時は 409 Conflict + Order は作られない" do
    headers = auth_headers(subdomain: subdomain, jwt: jwt)

    post "/storefront/cart/items", params: { variant_id: variant.id, quantity: 99 }.to_json, headers: headers
    expect(response).to have_http_status(:created)

    post "/storefront/checkout", params: {}.to_json, headers: headers
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body["error"]).to eq("insufficient_stock")
    expect(response.parsed_body["variant_id"]).to eq(variant.id)

    expect(Orders::Order.count).to eq(0)
    expect(Inventory::InventoryLevel.find_by(variant: variant, location: location).on_hand).to eq(3)
  end

  it "未認証は 401 (cart 操作)" do
    headers = { "X-Shop-Subdomain" => subdomain, "Content-Type" => "application/json", "Accept" => "application/json" }
    get "/storefront/cart", headers: headers
    expect(response).to have_http_status(:unauthorized)
  end
end
