require "rails_helper"

# Phase 4 / ADR 0003 の境界仕様:
# CheckoutService は Order 作成と Inventory::DeductService を **同一トランザクション**で実行する。
# 1 SKU でも在庫不足なら、Order・OrderItem・他の SKU の減算すべて rollback されることを実証。
RSpec.describe Orders::CheckoutService do
  let(:shop) { Core::Shop.create!(subdomain: "acme", name: "ACME") }
  let(:other_shop) { Core::Shop.create!(subdomain: "globex", name: "Globex") }
  let(:customer) { Core::User.create!(shop: shop, email: "buyer@example.com") }
  let(:product) { Catalog::Product.create!(shop: shop, slug: "tee", title: "Tee") }
  let(:variant_a) { Catalog::Variant.create!(shop: shop, product: product, sku: "A", price_cents: 1000, currency: "JPY") }
  let(:variant_b) { Catalog::Variant.create!(shop: shop, product: product, sku: "B", price_cents: 2000, currency: "JPY") }
  let(:location) { Inventory::Location.create!(shop: shop, name: "main", kind: "warehouse") }

  before do
    Inventory::InventoryLevel.create!(shop: shop, variant: variant_a, location: location, on_hand: 5)
    Inventory::InventoryLevel.create!(shop: shop, variant: variant_b, location: location, on_hand: 5)
  end

  def open_cart_with(items)
    cart = Orders::Cart.create!(shop: shop, customer: customer, status: :open)
    items.each do |variant, qty|
      Orders::CartItem.create!(shop: shop, cart: cart, variant: variant, quantity: qty)
    end
    cart
  end

  it "在庫が足りる時: Order + OrderItem 作成 / 在庫減算 / cart は completed" do
    cart = open_cart_with([ [ variant_a, 2 ], [ variant_b, 1 ] ])

    order = described_class.call(cart: cart, location: location)

    expect(order).to be_persisted
    expect(order.number).to eq(1)
    expect(order.total_cents).to eq(1000 * 2 + 2000)
    expect(order.items.count).to eq(2)
    expect(order.items.find_by(variant: variant_a).unit_price_cents).to eq(1000)

    expect(Inventory::InventoryLevel.find_by(variant: variant_a, location: location).on_hand).to eq(3)
    expect(Inventory::InventoryLevel.find_by(variant: variant_b, location: location).on_hand).to eq(4)
    expect(cart.reload.status).to eq("completed")
  end

  it "1 SKU でも在庫不足なら Order 全体が rollback される (ADR 0003 の不変条件)" do
    cart = open_cart_with([ [ variant_a, 2 ], [ variant_b, 99 ] ])  # b が足りない

    expect {
      described_class.call(cart: cart, location: location)
    }.to raise_error(Inventory::InsufficientStock)

    # 全件 rollback の確認
    expect(Orders::Order.count).to eq(0)
    expect(Orders::OrderItem.count).to eq(0)
    expect(Inventory::InventoryLevel.find_by(variant: variant_a, location: location).on_hand).to eq(5)
    expect(Inventory::InventoryLevel.find_by(variant: variant_b, location: location).on_hand).to eq(5)
    expect(Inventory::StockMovement.count).to eq(0)
    expect(cart.reload.status).to eq("open")
  end

  it "Order#number は shop 単位でシーケンシャル (1, 2, 3, ...)" do
    3.times do
      cart = open_cart_with([ [ variant_a, 1 ] ])
      described_class.call(cart: cart, location: location)
    end
    expect(Orders::Order.where(shop: shop).pluck(:number).sort).to eq([ 1, 2, 3 ])
  end

  it "完了済みの cart からは checkout できない" do
    cart = open_cart_with([ [ variant_a, 1 ] ])
    cart.update!(status: :completed)
    expect { described_class.call(cart: cart, location: location) }.to raise_error(Orders::CheckoutError, /not open/)
  end

  it "空 cart は EmptyCartError" do
    cart = Orders::Cart.create!(shop: shop, customer: customer, status: :open)
    expect { described_class.call(cart: cart, location: location) }.to raise_error(Orders::EmptyCartError)
  end

  it "別 shop の location では checkout できない" do
    cart = open_cart_with([ [ variant_a, 1 ] ])
    other_loc = Inventory::Location.create!(shop: other_shop, name: "main", kind: "warehouse")
    expect { described_class.call(cart: cart, location: other_loc) }.to raise_error(Orders::CheckoutError, /same shop/)
  end

  # Review fix C3
  it "C3: cart に複数 currency が混じっていると CurrencyMismatchError" do
    variant_usd = Catalog::Variant.create!(shop: shop, product: product, sku: "C", price_cents: 999, currency: "USD")
    Inventory::InventoryLevel.create!(shop: shop, variant: variant_usd, location: location, on_hand: 5)
    cart = open_cart_with([ [ variant_a, 1 ], [ variant_usd, 1 ] ])

    expect { described_class.call(cart: cart, location: location) }.to raise_error(Orders::CurrencyMismatchError, /multiple currencies/)
    expect(Orders::Order.count).to eq(0)
  end

  # Review fix I2
  it "I2: ledger の StockMovement に source_type/source_id が Order と紐づいて記録される" do
    cart = open_cart_with([ [ variant_a, 1 ] ])
    order = described_class.call(cart: cart, location: location)

    movement = Inventory::StockMovement.find_by(variant_id: variant_a.id, location_id: location.id)
    expect(movement.source_type).to eq("Orders::Order")
    expect(movement.source_id).to eq(order.id)
  end
end
