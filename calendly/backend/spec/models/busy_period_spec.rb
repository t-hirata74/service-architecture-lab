require "rails_helper"

RSpec.describe BusyPeriod do
  describe "validations" do
    it "requires end_at after start_at" do
      bp = build(:busy_period, start_at: Time.utc(2026, 6, 1, 10), end_at: Time.utc(2026, 6, 1, 10))
      expect(bp).not_to be_valid
    end

    it "rejects unknown source" do
      expect(build(:busy_period, source: "ical")).not_to be_valid
    end
  end

  describe ".overlapping" do
    let(:host) { create(:host) }
    let!(:bp) { create(:busy_period, host: host, start_at: Time.utc(2026, 6, 1, 10), end_at: Time.utc(2026, 6, 1, 11)) }

    it "matches strictly overlapping interval" do
      expect(host.busy_periods.overlapping(Time.utc(2026, 6, 1, 10, 30), Time.utc(2026, 6, 1, 10, 45))).to include(bp)
    end

    it "does not match adjacent (closed-open) interval" do
      # 09:00-10:00 と 10:00-11:00 は overlap しない (ADR 0001 closed-open)
      expect(host.busy_periods.overlapping(Time.utc(2026, 6, 1, 9), Time.utc(2026, 6, 1, 10))).to be_empty
    end

    it "matches partial overlap on left edge" do
      expect(host.busy_periods.overlapping(Time.utc(2026, 6, 1, 9, 30), Time.utc(2026, 6, 1, 10, 30))).to include(bp)
    end
  end
end
