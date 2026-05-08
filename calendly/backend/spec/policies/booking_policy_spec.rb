require "rails_helper"

RSpec.describe BookingPolicy do
  let(:host) { create(:host) }
  let(:other_host) { create(:host) }
  let(:event_type) { create(:event_type, host: host) }
  let(:booking) { create(:booking, host: host, event_type: event_type) }

  describe "#show?" do
    it "permits owner host" do
      expect(described_class.new(host, booking).show?).to be true
    end

    it "denies non-owner host" do
      expect(described_class.new(other_host, booking).show?).to be false
    end

    it "denies anonymous (invitee identity check is done in controller)" do
      expect(described_class.new(nil, booking).show?).to be false
    end
  end

  describe "#create?" do
    it "permits anyone (controller validates event_type.active)" do
      expect(described_class.new(nil, Booking.new).create?).to be true
      expect(described_class.new(host, Booking.new).create?).to be true
    end
  end

  describe "Scope" do
    it "returns only host's bookings" do
      b1 = create(:booking, host: host, event_type: event_type)
      other_event = create(:event_type, host: other_host)
      _b2 = create(:booking, host: other_host, event_type: other_event)
      resolved = BookingPolicy::Scope.new(host, Booking).resolve
      expect(resolved).to contain_exactly(b1, booking)
    end
  end
end
