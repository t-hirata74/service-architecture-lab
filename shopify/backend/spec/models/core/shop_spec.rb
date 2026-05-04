require "rails_helper"

RSpec.describe Core::Shop do
  it "subdomain と name が必須" do
    expect(described_class.new).not_to be_valid
  end

  it "subdomain は一意" do
    described_class.create!(subdomain: "acme", name: "ACME")
    dup = described_class.new(subdomain: "acme", name: "ACME 2")
    expect(dup).not_to be_valid
  end

  it "subdomain は小文字英数とハイフンのみ" do
    expect(described_class.new(subdomain: "Acme_Store", name: "X")).not_to be_valid
    expect(described_class.new(subdomain: "acme-store", name: "X")).to be_valid
  end
end
