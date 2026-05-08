require "rails_helper"

RSpec.describe Host do
  describe "validations" do
    it "requires email / name / default_tz_id" do
      h = Host.new
      expect(h).not_to be_valid
      expect(h.errors[:email]).to be_present
      expect(h.errors[:name]).to be_present
    end

    it "rejects offset string as default_tz_id (ADR 0003 — IANA tz id only)" do
      h = build(:host, default_tz_id: "+09:00")
      expect(h).not_to be_valid
      expect(h.errors[:default_tz_id]).to be_present
    end

    it "accepts IANA tz id" do
      expect(build(:host, default_tz_id: "Asia/Tokyo")).to be_valid
      expect(build(:host, default_tz_id: "America/New_York")).to be_valid
    end

    it "enforces email uniqueness (case insensitive)" do
      create(:host, email: "alice@example.com")
      expect(build(:host, email: "ALICE@example.com")).not_to be_valid
    end
  end

  # review fix I-C-1
  describe "Account との email 同期" do
    it "Host が Account を持つとき、Host#update(email:) が Account.email にも反映される" do
      account = Account.create!(email: "old@example.com", status: "verified", password_hash: "x")
      host = Host.create!(id: account.id, email: "old@example.com", name: "Alice", default_tz_id: "Asia/Tokyo")
      expect(host.account).to eq(account)

      host.update!(email: "new@example.com")
      expect(account.reload.email).to eq("new@example.com")
    end

    it "Account が無い (orphan) Host の update は raise しない" do
      host = Host.create!(email: "alice@example.com", name: "Alice", default_tz_id: "Asia/Tokyo")
      expect { host.update!(email: "alice2@example.com") }.not_to raise_error
    end
  end
end
