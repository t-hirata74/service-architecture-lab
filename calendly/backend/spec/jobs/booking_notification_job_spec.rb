require "rails_helper"

RSpec.describe BookingNotificationJob do
  let(:booking) { create(:booking) }

  it 'logs 2 notifications on "created" event (host + invitee)' do
    expect(Rails.logger).to receive(:info)
      .with(/\[BookingNotificationJob\].*New booking from/).once
    expect(Rails.logger).to receive(:info)
      .with(/\[BookingNotificationJob\].*Your booking is confirmed/).once
    allow(Rails.logger).to receive(:info).and_call_original
    described_class.perform_now(booking.id, "created")
  end

  it 'logs 2 notifications on "cancelled" event' do
    expect(Rails.logger).to receive(:info)
      .with(/\[BookingNotificationJob\].*cancelled by/).once
    expect(Rails.logger).to receive(:info)
      .with(/\[BookingNotificationJob\].*has been cancelled/).once
    allow(Rails.logger).to receive(:info).and_call_original
    described_class.perform_now(booking.id, "cancelled")
  end

  it "is idempotent on missing booking_id (deleted booking)" do
    booking.destroy!
    expect { described_class.perform_now(booking.id, "created") }.not_to raise_error
  end

  it "discards ArgumentError on unknown event (does not retry)" do
    # discard_on は perform_now でも例外を吸収する。Rails.logger.error の警告だけ出る。
    expect { described_class.perform_now(booking.id, "exploded") }.not_to raise_error
  end
end
