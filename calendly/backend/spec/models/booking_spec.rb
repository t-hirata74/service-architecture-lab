require "rails_helper"

RSpec.describe Booking do
  describe "validations" do
    it "requires end_at after start_at" do
      b = build(:booking, start_at: Time.utc(2026, 6, 1, 10), end_at: Time.utc(2026, 6, 1, 10))
      expect(b).not_to be_valid
    end

    it "validates status in STATUSES" do
      expect(build(:booking, status: "unknown")).not_to be_valid
    end

    it "validates invitee_tz_id is IANA tz id" do
      expect(build(:booking, invitee_tz_id: "+05:00")).not_to be_valid
    end
  end

  describe ".overlapping" do
    let(:host) { create(:host) }
    let(:event_type) { create(:event_type, host: host, duration_minutes: 60) }
    let!(:b) { create(:booking, host: host, event_type: event_type,
                       start_at: Time.utc(2026, 6, 1, 10), end_at: Time.utc(2026, 6, 1, 11),
                       status: "confirmed") }

    it "matches confirmed booking that overlaps" do
      expect(Booking.overlapping(host.id, Time.utc(2026, 6, 1, 10, 30), Time.utc(2026, 6, 1, 11, 30)))
        .to include(b)
    end

    it "ignores cancelled bookings (ADR 0002)" do
      b.update!(status: "cancelled")
      expect(Booking.overlapping(host.id, Time.utc(2026, 6, 1, 10, 30), Time.utc(2026, 6, 1, 11, 30)))
        .to be_empty
    end

    it "treats adjacent intervals as non-overlapping (closed-open)" do
      expect(Booking.overlapping(host.id, Time.utc(2026, 6, 1, 11), Time.utc(2026, 6, 1, 12)))
        .to be_empty
      expect(Booking.overlapping(host.id, Time.utc(2026, 6, 1, 9), Time.utc(2026, 6, 1, 10)))
        .to be_empty
    end

    it "scopes to host_id" do
      other_host = create(:host)
      expect(Booking.overlapping(other_host.id, Time.utc(2026, 6, 1, 10, 30), Time.utc(2026, 6, 1, 11, 30)))
        .to be_empty
    end
  end

  describe "#cancel!" do
    let(:b) { create(:booking, status: "confirmed") }

    it "transitions confirmed → cancelled" do
      b.cancel!
      expect(b).to be_cancelled
    end

    it "is idempotent on cancelled" do
      b.update!(status: "cancelled")
      expect { b.cancel! }.not_to raise_error
    end

    it "raises InvalidTransition from completed" do
      b.update!(status: "completed")
      expect { b.cancel! }.to raise_error(Booking::InvalidTransition)
    end
  end
end
