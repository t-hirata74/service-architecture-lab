require "rails_helper"

RSpec.describe Catalog::Product do
  let(:shop_a) { Core::Shop.create!(subdomain: "acme", name: "ACME") }
  let(:shop_b) { Core::Shop.create!(subdomain: "globex", name: "Globex") }

  it "shop / slug / title が必須" do
    expect(described_class.new).not_to be_valid
  end

  it "slug は同一 shop 内で一意 / 別 shop なら同じ slug でも OK" do
    described_class.create!(shop: shop_a, slug: "tee", title: "Tee")
    expect(described_class.new(shop: shop_a, slug: "tee", title: "Other")).not_to be_valid
    expect(described_class.new(shop: shop_b, slug: "tee", title: "Same name")).to be_valid
  end

  it "TenantOwned を include している" do
    expect(described_class.included_modules).to include(TenantOwned)
  end
end
