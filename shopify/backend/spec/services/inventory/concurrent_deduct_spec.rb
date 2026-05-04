require "rails_helper"

# ADR 0003 の核心不変条件:
# 「N 並行 thread から同一 SKU を同時に減算しても、negative on_hand は絶対に出ない」
#
# 条件付き UPDATE (`WHERE on_hand >= :q`) が悲観ロック無しで原子性を提供することを実証する。
# 100 thread から 1 個ずつ deduct を試行 / 在庫は 60 個 → 60 個成功 + 40 個 InsufficientStock を期待。
#
# transactional fixtures は OFF (thread が別 connection / transaction を持つため)。
# 後始末は after で truncate-style に明示削除する。
RSpec.describe "Inventory::DeductService — concurrent decrement (ADR 0003)" do
  self.use_transactional_tests = false

  let(:shop) { Core::Shop.create!(subdomain: "concurrent-#{SecureRandom.hex(4)}", name: "C") }
  let(:product) { Catalog::Product.create!(shop: shop, slug: "tee-#{SecureRandom.hex(4)}", title: "Tee") }
  let(:variant) { Catalog::Variant.create!(shop: shop, product: product, sku: "TEE-#{SecureRandom.hex(4)}", price_cents: 1000) }
  let(:location) { Inventory::Location.create!(shop: shop, name: "main", kind: "warehouse") }

  let(:initial) { 60 }
  let(:thread_count) { 100 }

  before do
    Inventory::InventoryLevel.create!(shop: shop, variant: variant, location: location, on_hand: initial)
  end

  after do
    # transactional fixtures を切ったので明示クリーンアップ
    Inventory::StockMovement.where(shop_id: shop.id).delete_all
    Inventory::InventoryLevel.where(shop_id: shop.id).delete_all
    Inventory::Location.where(shop_id: shop.id).delete_all
    Catalog::Variant.where(shop_id: shop.id).delete_all
    Catalog::Product.where(shop_id: shop.id).delete_all
    shop.destroy
  end

  it "100 並行 thread が 1 個ずつ deduct → 成功 #{60} 件 / 失敗 40 件 / on_hand == 0 / ledger 一貫" do
    success = Concurrent::AtomicFixnum.new(0) if defined?(Concurrent::AtomicFixnum)
    success_count = 0
    fail_count = 0
    mutex = Mutex.new
    barrier = Concurrent::CyclicBarrier.new(thread_count) if defined?(Concurrent::CyclicBarrier)

    threads = thread_count.times.map do
      Thread.new do
        # 全 thread が出揃うまで wait (concurrent な突入を強制)
        barrier&.wait
        ActiveRecord::Base.connection_pool.with_connection do
          Inventory::DeductService.call(
            shop: shop, variant: variant, location: location, quantity: 1, reason: "order_deduct"
          )
          mutex.synchronize { success_count += 1 }
        rescue Inventory::InsufficientStock
          mutex.synchronize { fail_count += 1 }
        end
      end
    end
    threads.each(&:join)

    expect(success_count).to eq(initial)
    expect(fail_count).to eq(thread_count - initial)
    expect(Inventory::InventoryLevel.find_by(variant_id: variant.id, location_id: location.id).on_hand).to eq(0)

    # ledger 不変条件: SUM(delta) == -initial (= -60)
    sum_delta = Inventory::StockMovement.where(variant_id: variant.id, location_id: location.id).sum(:delta)
    expect(sum_delta).to eq(-initial)

    # 成功した数だけ ledger 行が刻まれている
    expect(Inventory::StockMovement.where(variant_id: variant.id, location_id: location.id).count).to eq(initial)
  end
end
