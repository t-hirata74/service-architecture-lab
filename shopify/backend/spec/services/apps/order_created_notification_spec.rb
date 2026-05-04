require "rails_helper"

# ADR 0001 (依存方向 apps → orders) + ADR 0004:
# orders は ActiveSupport::Notifications で `orders.order_created` を publish するだけ。
# apps Engine の subscriber が拾って WebhookDelivery を作って enqueue する。
# orders 側は apps を一切参照していない (packwerk の dependency_spec で fixate 済み)。
RSpec.describe "Order created → webhook delivery (cross-engine integration)" do
  let(:shop) { Core::Shop.create!(subdomain: "acme", name: "ACME") }
  let(:customer) { Core::User.create!(shop: shop, email: "buyer@example.com") }
  let(:product) { Catalog::Product.create!(shop: shop, slug: "tee", title: "Tee") }
  let(:variant) { Catalog::Variant.create!(shop: shop, product: product, sku: "TEE", price_cents: 1000, currency: "JPY") }
  let(:location) { Inventory::Location.create!(shop: shop, name: "main", kind: "warehouse") }
  let(:app) { Apps::App.create!(name: "shipping-app", secret: "supersecret-1234567890") }
  let(:install) do
    Apps::AppInstallation.create!(shop: shop, app: app, scopes: "read_orders",
                                  api_token_digest: Apps::AppInstallation.digest_token(SecureRandom.hex(16)))
  end

  before do
    ActiveJob::Base.queue_adapter = :test
    Inventory::InventoryLevel.create!(shop: shop, variant: variant, location: location, on_hand: 5)
    Apps::WebhookSubscription.create!(shop: shop, app_installation: install,
                                      topic: "order_created", endpoint: "https://app.example.com/hook")
  end

  it "checkout 成功 → WebhookDelivery が pending で 1 件作られ DeliveryJob が enqueue される" do
    cart = Orders::Cart.create!(shop: shop, customer: customer, status: :open)
    Orders::CartItem.create!(shop: shop, cart: cart, variant: variant, quantity: 2)

    expect {
      Orders::CheckoutService.call(cart: cart, location: location)
    }.to change(Apps::WebhookDelivery, :count).by(1)
      .and have_enqueued_job(Apps::DeliveryJob)

    delivery = Apps::WebhookDelivery.last
    expect(delivery.topic).to eq("order_created")
    expect(delivery).to be_pending
    payload = delivery.parsed_payload
    expect(payload["number"]).to eq(1)
    expect(payload["total_cents"]).to eq(2000)
  end

  it "subscription が 0 件なら delivery も 0 件 (publish は no-op)" do
    Apps::WebhookSubscription.delete_all
    cart = Orders::Cart.create!(shop: shop, customer: customer, status: :open)
    Orders::CartItem.create!(shop: shop, cart: cart, variant: variant, quantity: 1)

    expect {
      Orders::CheckoutService.call(cart: cart, location: location)
    }.not_to change(Apps::WebhookDelivery, :count)
  end
end
