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
end
