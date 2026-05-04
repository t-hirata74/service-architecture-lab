require "rails_helper"

RSpec.describe Catalog::Variant do
  let(:shop_a) { Core::Shop.create!(subdomain: "acme", name: "ACME") }
  let(:shop_b) { Core::Shop.create!(subdomain: "globex", name: "Globex") }
  let(:product_a) { Catalog::Product.create!(shop: shop_a, slug: "tee", title: "Tee") }
  let(:product_b) { Catalog::Product.create!(shop: shop_b, slug: "tee", title: "Tee Globex") }

  it "sku / price_cents / currency が validate される" do
    v = described_class.new(shop: shop_a, product: product_a, sku: "TEE-S", price_cents: 1000, currency: "JPY")
    expect(v).to be_valid
    expect(described_class.new(shop: shop_a, product: product_a, sku: "TEE-S", price_cents: -1, currency: "JPY")).not_to be_valid
    expect(described_class.new(shop: shop_a, product: product_a, sku: "TEE-S", price_cents: 1000, currency: "JP")).not_to be_valid
  end

  it "sku は同一 shop 内で一意" do
    described_class.create!(shop: shop_a, product: product_a, sku: "TEE-S", price_cents: 1000)
    expect(described_class.new(shop: shop_a, product: product_a, sku: "TEE-S", price_cents: 1000)).not_to be_valid
  end

  it "product と shop は同一 tenant でなければならない" do
    v = described_class.new(shop: shop_a, product: product_b, sku: "X", price_cents: 100)
    expect(v).not_to be_valid
    expect(v.errors[:product]).to include(/same shop/)
  end
end
