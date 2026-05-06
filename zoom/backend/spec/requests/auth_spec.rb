require "rails_helper"

# Phase 4-3: rodauth-rails の signup → login フローを fixate する。
# - POST /create-account: accounts row 作成 + after_create_account hook で users row 作成
# - POST /login: JWT を Authorization ヘッダで返す
RSpec.describe "Authentication", type: :request do
  describe "POST /create-account" do
    let(:params) { { email: "alice@example.test", password: "password123", display_name: "Alice" } }

    it "accounts と users の両方に 1 行作成され、status は verified" do
      expect {
        post "/create-account", params: params, as: :json
      }.to change { Account.count }.by(1)
        .and change { User.count }.by(1)

      expect(response).to have_http_status(:ok).or have_http_status(:created)
      account = Account.last
      user = User.last
      expect(account.email).to eq("alice@example.test")
      expect(account.status).to eq("verified")
      expect(user.id).to eq(account.id)
      expect(user.email).to eq("alice@example.test")
      expect(user.display_name).to eq("Alice")
    end

    it "display_name が無いと 422" do
      post "/create-account", params: params.except(:display_name), as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(Account.count).to eq(0)
      expect(User.count).to eq(0)
    end

    it "短すぎるパスワードは弾かれる" do
      post "/create-account", params: params.merge(password: "short"), as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "POST /login" do
    before do
      post "/create-account",
           params: { email: "bob@example.test", password: "password123", display_name: "Bob" },
           as: :json
    end

    it "成功すると JWT が Authorization ヘッダに乗り、payload に account_id が含まれる" do
      post "/login", params: { email: "bob@example.test", password: "password123" }, as: :json
      expect(response).to have_http_status(:ok)
      token = response.headers["Authorization"]
      expect(token).to be_present

      # rodauth-jwt は素の JWT を Authorization ヘッダにそのまま入れる (Bearer 接頭辞なし)。
      # 利用側では `Authorization: Bearer <token>` で送り直すのが慣習。
      payload, _header = JWT.decode(token, ENV.fetch("RODAUTH_JWT_SECRET", Rails.application.secret_key_base))
      expect(payload["account_id"]).to eq(Account.find_by(email: "bob@example.test").id)
    end

    it "誤ったパスワードは 401 / 422、JWT に account_id は含まれない" do
      post "/login", params: { email: "bob@example.test", password: "wrong" }, as: :json
      expect(response.status).to be_in([401, 422])

      token = response.headers["Authorization"]
      if token.present?
        payload, _ = JWT.decode(token, ENV.fetch("RODAUTH_JWT_SECRET", Rails.application.secret_key_base))
        expect(payload["account_id"]).to be_nil
      end
    end

    it "存在しないアカウントは 401" do
      post "/login", params: { email: "ghost@example.test", password: "password123" }, as: :json
      expect(response).to have_http_status(:unauthorized).or have_http_status(:unprocessable_entity)
    end
  end
end
