require "rails_helper"

# Review fix C1 / I3 の不変条件を実証する spec:
#   - 同一 cart に対する並行 checkout は 1 つだけ成功し、もう一方は CheckoutError か
#     ActiveRecord::Deadlocked で失敗する (二重課金しない)
#   - Order#number は shop 単位のシーケンシャル採番 (重複しない)
#   - 並行 checkout 後、在庫減算は 1 回分だけ
#
# transactional fixtures は OFF (thread が別 connection / transaction を持つため)。
# 後始末は after で truncate-style に明示削除する。
RSpec.describe "Orders::CheckoutService — concurrent checkout safety (review C1/I3)" do
  self.use_transactional_tests = false

  let(:shop) { Core::Shop.create!(subdomain: "concheck-#{SecureRandom.hex(3)}", name: "Conc") }
  let(:customer) { Core::User.create!(shop: shop, email: "buyer-#{SecureRandom.hex(2)}@x.com") }
  let(:product) { Catalog::Product.create!(shop: shop, slug: "tee-#{SecureRandom.hex(2)}", title: "Tee") }
  let(:variant) { Catalog::Variant.create!(shop: shop, product: product, sku: "TEE-#{SecureRandom.hex(2)}", price_cents: 1000, currency: "JPY") }
  let(:location) { Inventory::Location.create!(shop: shop, name: "main", kind: "warehouse") }

  before do
    Inventory::InventoryLevel.create!(shop: shop, variant: variant, location: location, on_hand: 10)
  end

  after do
    Inventory::StockMovement.where(shop_id: shop.id).delete_all
    Orders::OrderItem.where(shop_id: shop.id).delete_all
    Orders::Order.where(shop_id: shop.id).delete_all
    Orders::CartItem.where(shop_id: shop.id).delete_all
    Orders::Cart.where(shop_id: shop.id).delete_all
    Inventory::InventoryLevel.where(shop_id: shop.id).delete_all
    Inventory::Location.where(shop_id: shop.id).delete_all
    Catalog::Variant.where(shop_id: shop.id).delete_all
    Catalog::Product.where(shop_id: shop.id).delete_all
    Core::User.where(shop_id: shop.id).delete_all
    shop.destroy
  end

  it "C1: 同一 cart への 5 並行 checkout でも、注文・在庫減算は厳密に 1 回だけ起きる" do
    cart = Orders::Cart.create!(shop: shop, customer: customer, status: :open)
    Orders::CartItem.create!(shop: shop, cart: cart, variant: variant, quantity: 2)

    success_count = 0
    failures = []
    mutex = Mutex.new
    barrier = Concurrent::CyclicBarrier.new(5)

    threads = 5.times.map do
      Thread.new do
        barrier.wait
        ActiveRecord::Base.connection_pool.with_connection do
          cart_t = Orders::Cart.find(cart.id)
          Orders::CheckoutService.call(cart: cart_t, location: location)
          mutex.synchronize { success_count += 1 }
        rescue StandardError => e
          mutex.synchronize { failures << e.class.name }
        end
      end
    end
    threads.each(&:join)

    expect(success_count).to eq(1)
    expect(failures.size).to eq(4)
    # 失敗は CheckoutError ("not open") か ActiveRecord::Deadlocked のいずれか
    expect(failures).to all(satisfy { |c| c == "Orders::CheckoutError" || c == "ActiveRecord::Deadlocked" })

    expect(Orders::Order.where(shop_id: shop.id).count).to eq(1)
    expect(Inventory::InventoryLevel.find_by(variant_id: variant.id, location_id: location.id).on_hand).to eq(8)
    expect(Inventory::StockMovement.where(shop_id: shop.id).count).to eq(1)
  end

  it "I3: 異なる cart に対する 5 並行 checkout でも Order#number は重複しない (1..5)" do
    customers = 5.times.map { |i| Core::User.create!(shop: shop, email: "buyer#{i}-#{SecureRandom.hex(2)}@x.com") }
    carts = customers.map do |c|
      cart = Orders::Cart.create!(shop: shop, customer: c, status: :open)
      Orders::CartItem.create!(shop: shop, cart: cart, variant: variant, quantity: 1)
      cart
    end

    barrier = Concurrent::CyclicBarrier.new(carts.size)
    threads = carts.map do |cart|
      Thread.new do
        barrier.wait
        ActiveRecord::Base.connection_pool.with_connection do
          Orders::CheckoutService.call(cart: cart, location: location)
        end
      end
    end
    threads.each(&:join)

    numbers = Orders::Order.where(shop_id: shop.id).pluck(:number).sort
    expect(numbers).to eq([ 1, 2, 3, 4, 5 ])
    expect(numbers.uniq).to eq(numbers) # 重複なし
  end
end
