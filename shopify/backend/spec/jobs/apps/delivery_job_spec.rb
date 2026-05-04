require "rails_helper"
require "webmock/rspec"

# ADR 0004 の不変条件:
#   - 2xx 受信 → status=delivered, delivered_at が立つ
#   - 5xx 受信 → status=pending のまま、attempts++、再 enqueue
#   - MAX_ATTEMPTS 到達 → status=failed_permanent
#   - 4xx 受信 → 即 failed_permanent (retry しない)
#   - HMAC 署名と X-Webhook-Delivery-Id を必ず送る (受信側冪等性のための契約)
RSpec.describe Apps::DeliveryJob do
  let(:shop) { Core::Shop.create!(subdomain: "acme", name: "ACME") }
  let(:app) { Apps::App.create!(name: "shipping-app", secret: "supersecret-1234567890") }
  let(:install) do
    Apps::AppInstallation.create!(
      shop: shop, app: app, scopes: "read_orders",
      api_token_digest: Apps::AppInstallation.digest_token(SecureRandom.hex(16))
    )
  end
  let(:endpoint) { "https://app.example.com/hooks/order" }
  let(:subscription) do
    Apps::WebhookSubscription.create!(shop: shop, app_installation: install,
                                      topic: "order_created", endpoint: endpoint)
  end
  let(:payload_json) { %({"order_id":42}) }
  let!(:delivery) do
    Apps::WebhookDelivery.create!(
      shop: shop, subscription: subscription,
      delivery_id: "abc-123", topic: "order_created", payload: payload_json
    )
  end

  before { ActiveJob::Base.queue_adapter = :test }

  it "2xx 受信で delivered になり、HMAC + delivery_id ヘッダ付きで POST する" do
    captured = nil
    stub = stub_request(:post, endpoint)
      .to_return(status: 200, body: "ok")
      .with { |req| captured = req; true }

    described_class.perform_now(delivery.id)

    expect(stub).to have_been_made
    expect(delivery.reload).to be_delivered
    expect(delivery.delivered_at).to be_present
    expect(delivery.attempts).to eq(1)

    # HMAC 署名と delivery_id が送られている (受信側冪等性の契約)
    expected_sig = Apps::Signer.sign(secret: app.secret, body: payload_json)
    expect(captured.headers[Apps::Signer::HEADER_HMAC]).to eq(expected_sig)
    expect(captured.headers[Apps::Signer::HEADER_DELIVERY_ID]).to eq("abc-123")
    expect(captured.headers[Apps::Signer::HEADER_TOPIC]).to eq("order_created")
  end

  it "5xx 受信は pending 維持で attempts++ + 再 enqueue (retry)" do
    stub_request(:post, endpoint).to_return(status: 503, body: "down")

    expect {
      described_class.perform_now(delivery.id)
    }.to have_enqueued_job(Apps::DeliveryJob)

    expect(delivery.reload).to be_pending
    expect(delivery.attempts).to eq(1)
    expect(delivery.last_error).to eq("HTTP 503")
    expect(delivery.next_attempt_at).to be > Time.current
  end

  it "MAX_ATTEMPTS 到達後の失敗は failed_permanent" do
    delivery.update!(attempts: Apps::WebhookDelivery::MAX_ATTEMPTS - 1)
    stub_request(:post, endpoint).to_return(status: 503)

    described_class.perform_now(delivery.id)

    expect(delivery.reload).to be_failed_permanent
    expect(delivery.attempts).to eq(Apps::WebhookDelivery::MAX_ATTEMPTS)
  end

  it "4xx 受信は即 failed_permanent (retry しない)" do
    stub_request(:post, endpoint).to_return(status: 400, body: "bad")

    expect {
      described_class.perform_now(delivery.id)
    }.not_to have_enqueued_job(Apps::DeliveryJob)

    expect(delivery.reload).to be_failed_permanent
    expect(delivery.last_error).to include("HTTP 400")
  end

  it "delivered な配信は二重実行されても再 POST しない (idempotency)" do
    delivery.update!(status: :delivered, delivered_at: Time.current)
    expect {
      described_class.perform_now(delivery.id)
    }.not_to change { WebMock::RequestRegistry.instance.times_executed(WebMock::RequestPattern.new(:post, endpoint)) }
  end
end
