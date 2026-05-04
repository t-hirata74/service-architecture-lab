require "rails_helper"
require "webmock/rspec"

# Review fix M8: backend → ai-worker /recommend の統合 spec。
# - ai-worker が想定通り応答した時、related Product を順序保ったまま返す
# - ai-worker が落ちている時、graceful degradation で degraded: true + 空配列を返す
RSpec.describe "GET /storefront/products/:slug/recommendations", type: :request do
  let!(:shop) { Core::Shop.create!(subdomain: "acme", name: "ACME") }
  let!(:tee) { Catalog::Product.create!(shop: shop, slug: "tee", title: "Tee", status: :active) }
  let!(:hoodie) { Catalog::Product.create!(shop: shop, slug: "hoodie", title: "Hoodie", status: :active) }
  let!(:cap) { Catalog::Product.create!(shop: shop, slug: "cap", title: "Cap", status: :active) }
  let!(:draft) { Catalog::Product.create!(shop: shop, slug: "draft", title: "Draft", status: :draft) }
  let(:headers) { { "X-Shop-Subdomain" => "acme" } }

  it "ai-worker /recommend を呼び related Product を返す" do
    stub_request(:post, "http://127.0.0.1:8070/recommend")
      .to_return(status: 200, body: { product_id: tee.id, related: [ hoodie.id, cap.id ] }.to_json,
                 headers: { "Content-Type" => "application/json" })

    get "/storefront/products/tee/recommendations", headers: headers
    expect(response).to have_http_status(:ok)

    body = response.parsed_body
    expect(body["product_id"]).to eq(tee.id)
    titles = body["related"].map { |p| p["title"] }
    expect(titles).to eq([ "Hoodie", "Cap" ])
  end

  it "ai-worker が落ちている時は degraded: true で空 related を返す" do
    stub_request(:post, "http://127.0.0.1:8070/recommend").to_raise(Errno::ECONNREFUSED)

    get "/storefront/products/tee/recommendations", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["related"]).to eq([])
    expect(response.parsed_body["degraded"]).to be(true)
  end

  it "draft product は recommendations 候補に含めない (active のみ)" do
    captured = nil
    stub_request(:post, "http://127.0.0.1:8070/recommend")
      .with { |req| captured = JSON.parse(req.body); true }
      .to_return(status: 200, body: { product_id: tee.id, related: [] }.to_json,
                 headers: { "Content-Type" => "application/json" })

    get "/storefront/products/tee/recommendations", headers: headers
    expect(response).to have_http_status(:ok)
    expect(captured["candidate_product_ids"]).to contain_exactly(hoodie.id, cap.id) # draft は除外
  end
end
