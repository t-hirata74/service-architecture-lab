require "rails_helper"

RSpec.describe Bookings::CreateService do
  let(:host) { create(:host) }
  let(:event_type) { create(:event_type, host: host, duration_minutes: 60) }

  def call(start_at:, email: "alice@example.com")
    described_class.new(event_type: event_type, start_at: start_at,
                        invitee_email: email, invitee_tz_id: "Asia/Tokyo").call
  end

  it "creates a confirmed booking when slot is free" do
    booking = call(start_at: Time.utc(2026, 6, 1, 9, 0))
    expect(booking).to be_persisted
    expect(booking).to be_confirmed
    expect(booking.end_at).to eq(Time.utc(2026, 6, 1, 10, 0))
  end

  it "raises BookingConflict on overlap with confirmed booking" do
    call(start_at: Time.utc(2026, 6, 1, 9, 0))
    expect { call(start_at: Time.utc(2026, 6, 1, 9, 30), email: "bob@example.com") }
      .to raise_error(described_class::BookingConflict)
  end

  it "allows back-to-back booking (closed-open ADR 0001)" do
    call(start_at: Time.utc(2026, 6, 1, 9, 0))
    expect { call(start_at: Time.utc(2026, 6, 1, 10, 0), email: "bob@example.com") }
      .not_to raise_error
  end

  it "allows re-booking after cancellation" do
    b = call(start_at: Time.utc(2026, 6, 1, 9, 0))
    b.cancel!
    expect { call(start_at: Time.utc(2026, 6, 1, 9, 0), email: "bob@example.com") }
      .not_to raise_error
  end

  it "raises BookingConflict when start_at overlaps with busy_period" do
    create(:busy_period, host: host,
           start_at: Time.utc(2026, 6, 1, 9, 0), end_at: Time.utc(2026, 6, 1, 10, 0))
    expect { call(start_at: Time.utc(2026, 6, 1, 9, 30)) }
      .to raise_error(described_class::BookingConflict)
  end
end
