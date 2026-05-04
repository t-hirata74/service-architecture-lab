require "rails_helper"

# ADR 0003: ledger は append-only。永続化済みのレコードを update / delete は model 経由で禁止する。
RSpec.describe Inventory::StockMovement do
  let(:shop) { Core::Shop.create!(subdomain: "acme", name: "ACME") }
  let(:product) { Catalog::Product.create!(shop: shop, slug: "tee", title: "Tee") }
  let(:variant) { Catalog::Variant.create!(shop: shop, product: product, sku: "TEE-S", price_cents: 1000) }
  let(:location) { Inventory::Location.create!(shop: shop, name: "main", kind: "warehouse") }

  it "永続化済みは readonly (update が ActiveRecord::ReadOnlyRecord)" do
    m = described_class.create!(shop: shop, variant: variant, location: location, delta: -1, reason: "order_deduct")
    expect { m.update!(delta: -5) }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  it "delta == 0 は不正 (整合性のための制約)" do
    m = described_class.new(shop: shop, variant: variant, location: location, delta: 0, reason: "adjustment")
    expect(m).not_to be_valid
  end

  it "未知の reason は弾く" do
    m = described_class.new(shop: shop, variant: variant, location: location, delta: -1, reason: "mystery")
    expect(m).not_to be_valid
  end
end
