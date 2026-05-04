require "rails_helper"

# ADR 0002: cross-tenant isolation の不変条件。
# 「Shop A のセッションで Shop B のリソースを引けない」を最小ケースで固定する。
# Phase 3 以降で Product / Order が増えたら同じ不変条件をそれぞれにも適用する。
RSpec.describe "Cross-tenant isolation", type: :model do
  let!(:acme)   { Core::Shop.create!(subdomain: "acme", name: "ACME") }
  let!(:globex) { Core::Shop.create!(subdomain: "globex", name: "Globex") }
  let!(:alice_at_acme)   { Core::User.create!(shop: acme,   email: "alice@example.com") }
  let!(:alice_at_globex) { Core::User.create!(shop: globex, email: "alice@example.com") }

  it "shop scope で別 shop のレコードを引けない (User)" do
    expect(acme.users).to contain_exactly(alice_at_acme)
    expect(globex.users).to contain_exactly(alice_at_globex)
  end

  it "明示 scope (current_shop.users.find) を使うと shop 跨ぎは 404 になる" do
    expect { acme.users.find(alice_at_globex.id) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it "shop_id 抜きで User は保存できない (TenantOwned 不変条件)" do
    user = Core::User.new(email: "bob@example.com")
    expect(user).not_to be_valid
    expect(user.errors[:shop]).to be_present
  end
end
