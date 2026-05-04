require "rails_helper"

# ADR 0004: publish は呼び出し側のトランザクションに乗る。
# subscription が無ければ何も作らない (no-op)。
# 同じ topic に複数 subscription があれば、件数分の WebhookDelivery を作る。
RSpec.describe Apps::EventBus do
  let(:shop) { Core::Shop.create!(subdomain: "acme", name: "ACME") }
  let(:app) { Apps::App.create!(name: "shipping-app", secret: "supersecret-1234567890") }
  let(:install) do
    Apps::AppInstallation.create!(
      shop: shop, app: app, scopes: "read_orders",
      api_token_digest: Apps::AppInstallation.digest_token(SecureRandom.hex(16))
    )
  end

  before do
    ActiveJob::Base.queue_adapter = :test
  end

  it "subscription が無ければ何も作らない" do
    expect {
      described_class.publish(topic: :order_created, payload: { x: 1 }, shop: shop)
    }.not_to change(Apps::WebhookDelivery, :count)
  end

  it "同 topic の subscription 件数だけ WebhookDelivery を作って enqueue する" do
    install
    sub1 = Apps::WebhookSubscription.create!(shop: shop, app_installation: install,
                                             topic: "order_created", endpoint: "https://app1.example.com/hook")
    sub2 = Apps::WebhookSubscription.create!(shop: shop, app_installation: install,
                                             topic: "order_created", endpoint: "https://app2.example.com/hook")

    expect {
      described_class.publish(topic: :order_created, payload: { order_id: 42 }, shop: shop)
    }.to change(Apps::WebhookDelivery, :count).by(2)
      .and have_enqueued_job(Apps::DeliveryJob).twice

    deliveries = Apps::WebhookDelivery.last(2)
    expect(deliveries.map(&:status).uniq).to eq([ "pending" ])
    expect(deliveries.map(&:delivery_id).uniq.size).to eq(2)
    expect(deliveries.map(&:topic).uniq).to eq([ "order_created" ])
    expect(deliveries.map(&:subscription_id)).to contain_exactly(sub1.id, sub2.id)
  end

  it "未知の topic は ArgumentError" do
    expect {
      described_class.publish(topic: :unknown_topic, payload: {}, shop: shop)
    }.to raise_error(ArgumentError, /unsupported topic/)
  end
end
