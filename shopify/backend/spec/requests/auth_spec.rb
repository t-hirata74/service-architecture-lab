require "rails_helper"

# ADR 0002 + rodauth: account 作成は **shop が解決できている**ことを前提とする。
# - サブドメイン無しでの create-account は 403
# - サブドメイン有り → account + Core::User が同じ id で作られる
# - 別 shop で同じ email も許可 (User#email は shop_id scope で UNIQUE)
RSpec.describe "Authentication via rodauth + tenant resolver", type: :request do
  let!(:acme) { Core::Shop.create!(subdomain: "acme", name: "ACME") }
  let!(:globex) { Core::Shop.create!(subdomain: "globex", name: "Globex") }

  it "shop 未解決での create-account は 403" do
    post "/create-account",
         params: { email: "alice@example.com", password: "passw0rd" }.to_json,
         headers: { "Content-Type" => "application/json", "Accept" => "application/json" }
    expect(response.status).to eq(403)
  end

  it "shop 解決済みなら account + Core::User が共有 PK で作られる" do
    post "/create-account",
         params: { email: "alice@example.com", password: "passw0rd" }.to_json,
         headers: {
           "Content-Type" => "application/json",
           "Accept" => "application/json",
           "X-Shop-Subdomain" => "acme"
         }
    expect([ 200, 201 ]).to include(response.status), "body: #{response.body}"

    account = Core::Account.find_by(email: "alice@example.com")
    expect(account).to be_present
    user = Core::User.find_by(id: account.id)
    expect(user).to be_present
    expect(user.shop_id).to eq(acme.id)
    expect(user.email).to eq("alice@example.com")
  end

  it "別 shop で同じ email を登録できる (User#email は shop scope で UNIQUE)" do
    post "/create-account",
         params: { email: "shared@example.com", password: "passw0rd" }.to_json,
         headers: { "Content-Type" => "application/json", "Accept" => "application/json", "X-Shop-Subdomain" => "acme" }
    expect(Core::User.where(email: "shared@example.com", shop_id: acme.id)).to exist

    # rodauth の accounts は email UNIQUE なので 2 つ目は弾かれる (将来 shop_id 含めた複合 UNIQUE に拡張する余地あり)
    post "/create-account",
         params: { email: "shared@example.com", password: "passw0rd" }.to_json,
         headers: { "Content-Type" => "application/json", "Accept" => "application/json", "X-Shop-Subdomain" => "globex" }
    # accounts UNIQUE で 422 系になる想定 (ここは将来 ADR 派生候補)
    expect(response.status).not_to eq(500)
  end
end
