require "rails_helper"

# Phase 4-3: rodauth-rails JWT bearer の統合テスト。
# zoom / shopify / perplexity と同形 (POST /create-account → POST /login → JWT bearer)。
RSpec.describe "Auth (rodauth-rails JWT)", type: :request do
  let(:json) { JSON.parse(response.body) rescue {} }

  describe "POST /create-account" do
    it "creates Account + Host (shared PK), returns JWT in Authorization header" do
      post "/create-account",
           params: { email: "alice@example.com", password: "supersecret123",
                     name: "Alice", default_tz_id: "Asia/Tokyo" }.to_json,
           headers: { "Content-Type" => "application/json", "Accept" => "application/json" }
      expect(response).to have_http_status(:ok), response.body

      account = Account.find_by(email: "alice@example.com")
      expect(account).to be_present
      host = Host.find(account.id)
      expect(host.email).to eq("alice@example.com")
      expect(host.name).to eq("Alice")
      expect(host.default_tz_id).to eq("Asia/Tokyo")

      # JWT が Authorization ヘッダで返る (rodauth-jwt 標準)
      expect(response.headers["Authorization"]).to be_present
    end

    it "rejects when name is missing (422)" do
      post "/create-account",
           params: { email: "bob@example.com", password: "supersecret123" }.to_json,
           headers: { "Content-Type" => "application/json", "Accept" => "application/json" }
      expect(response).to have_http_status(:unprocessable_entity)
      # rodauth は field-error を `field-error` キーで返す形式
      body = JSON.parse(response.body)
      expect(body.values.flatten).to include(/name required/i)
    end
  end

  describe "POST /login + Bearer auth" do
    before do
      post "/create-account",
           params: { email: "carol@example.com", password: "supersecret123",
                     name: "Carol", default_tz_id: "Asia/Tokyo" }.to_json,
           headers: { "Content-Type" => "application/json", "Accept" => "application/json" }
    end

    it "logs in and returns a JWT for subsequent requests" do
      post "/login",
           params: { email: "carol@example.com", password: "supersecret123" }.to_json,
           headers: { "Content-Type" => "application/json", "Accept" => "application/json" }
      expect(response).to have_http_status(:ok), response.body
      expect(response.headers["Authorization"]).to be_present
    end

    it "rejects wrong password (401)" do
      post "/login",
           params: { email: "carol@example.com", password: "WRONG-pw-123" }.to_json,
           headers: { "Content-Type" => "application/json", "Accept" => "application/json" }
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
