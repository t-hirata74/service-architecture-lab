require "rails_helper"

# ADR 0004: rodauth-rails JWT bearer の統合テスト (zoom / calendly と同形)。
RSpec.describe "Auth (rodauth-rails JWT)", type: :request do
  describe "POST /create-account" do
    it "Account + User を shared PK で作り、JWT を Authorization ヘッダで返す" do
      post "/create-account",
           params: { email: "alice@example.com", password: "supersecret123", name: "Alice" }.to_json,
           headers: json_headers
      expect(response).to have_http_status(:ok), response.body

      account = Account.find_by(email: "alice@example.com")
      expect(account).to be_present
      user = User.find(account.id)
      expect(user.name).to eq("Alice")
      expect(response.headers["Authorization"]).to be_present
    end

    it "name 欠落は 422" do
      post "/create-account",
           params: { email: "bob@example.com", password: "supersecret123" }.to_json,
           headers: json_headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body).values.flatten).to include(/name required/i)
    end
  end

  describe "Bearer auth" do
    it "JWT 付きで /me が引ける / 無しは 401" do
      _user, headers = signup(email: "carol@example.com", name: "Carol")

      get "/me", headers: headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["name"]).to eq("Carol")

      get "/me", headers: json_headers
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
