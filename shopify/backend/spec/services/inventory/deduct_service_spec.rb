require "rails_helper"

# ADR 0003: 在庫減算の単体仕様。
# - 通常の減算成功
# - 在庫不足時に Inventory::InsufficientStock を raise + ledger も書かない (rollback)
# - quantity 引数のバリデーション
# - cross-tenant な組合せは ArgumentError
RSpec.describe Inventory::DeductService do
  let(:shop) { Core::Shop.create!(subdomain: "acme", name: "ACME") }
  let(:other_shop) { Core::Shop.create!(subdomain: "globex", name: "Globex") }
  let(:product) { Catalog::Product.create!(shop: shop, slug: "tee", title: "Tee") }
  let(:variant) { Catalog::Variant.create!(shop: shop, product: product, sku: "TEE-S", price_cents: 1000) }
  let(:location) { Inventory::Location.create!(shop: shop, name: "main", kind: "warehouse") }
  let!(:level) { Inventory::InventoryLevel.create!(shop: shop, variant: variant, location: location, on_hand: 10) }

  it "在庫がある時は on_hand を減算し ledger に -delta を残す" do
    described_class.call(shop: shop, variant: variant, location: location, quantity: 3, reason: "order_deduct")
    expect(level.reload.on_hand).to eq(7)
    movement = Inventory::StockMovement.last
    expect(movement.delta).to eq(-3)
    expect(movement.reason).to eq("order_deduct")
  end

  it "source を渡すと StockMovement に source_type / source_id が記録される" do
    fake_order = Struct.new(:id).new(42)
    allow(fake_order).to receive(:class).and_return(Struct.new(:name) { def to_s; "Orders::Order"; end }.new("Orders::Order"))
    described_class.call(shop: shop, variant: variant, location: location, quantity: 1,
                         reason: "order_deduct", source: fake_order)
    expect(Inventory::StockMovement.last.source_id).to eq(42)
  end

  it "在庫不足は InsufficientStock を raise し、on_hand と ledger は変化しない" do
    expect {
      described_class.call(shop: shop, variant: variant, location: location, quantity: 100, reason: "order_deduct")
    }.to raise_error(Inventory::InsufficientStock)
    expect(level.reload.on_hand).to eq(10)
    expect(Inventory::StockMovement.count).to eq(0)
  end

  it "quantity が 0 以下なら ArgumentError" do
    expect {
      described_class.call(shop: shop, variant: variant, location: location, quantity: 0, reason: "order_deduct")
    }.to raise_error(ArgumentError, /positive/)
  end

  it "shop / variant / location が同一 tenant でなければ ArgumentError" do
    other_loc = Inventory::Location.create!(shop: other_shop, name: "main", kind: "warehouse")
    expect {
      described_class.call(shop: shop, variant: variant, location: other_loc, quantity: 1, reason: "order_deduct")
    }.to raise_error(ArgumentError, /same tenant/)
  end

  # Review fix I1: 行不在ケースは NotConfigured で区別する
  it "I1: InventoryLevel が無い variant への deduct は NotConfigured (InsufficientStock とは別)" do
    other_variant = Catalog::Variant.create!(shop: shop, product: product, sku: "NEW", price_cents: 500)
    expect {
      described_class.call(shop: shop, variant: other_variant, location: location, quantity: 1, reason: "order_deduct")
    }.to raise_error(Inventory::NotConfigured)
  end
end
