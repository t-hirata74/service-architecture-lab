require "rails_helper"

RSpec.describe Core::User do
  let(:shop_a) { Core::Shop.create!(subdomain: "acme", name: "ACME") }
  let(:shop_b) { Core::Shop.create!(subdomain: "globex", name: "Globex") }

  it "shop と email が必須 (TenantOwned concern)" do
    expect(described_class.new(email: "x@y.z")).not_to be_valid
    expect(described_class.new(shop: shop_a)).not_to be_valid
  end

  it "email は同一 shop 内で一意 / 別 shop なら同じ email も許可" do
    described_class.create!(shop: shop_a, email: "alice@example.com")
    expect(described_class.new(shop: shop_a, email: "alice@example.com")).not_to be_valid
    expect(described_class.new(shop: shop_b, email: "alice@example.com")).to be_valid
  end

  it "TenantOwned を include している (ADR 0002 不変条件)" do
    expect(described_class.included_modules).to include(TenantOwned)
  end
end
