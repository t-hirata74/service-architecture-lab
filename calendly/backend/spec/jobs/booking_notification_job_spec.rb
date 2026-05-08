require "rails_helper"

RSpec.describe BookingNotificationJob do
  let(:booking) { create(:booking) }

  it 'logs 2 notifications on "created" event (host + invitee)' do
    expect(Rails.logger).to receive(:info)
      .with(/\[BookingNotificationJob\].*subject="\[mock\] new_booking"/).once
    expect(Rails.logger).to receive(:info)
      .with(/\[BookingNotificationJob\].*subject="\[mock\] booking_confirmed"/).once
    allow(Rails.logger).to receive(:info).and_call_original
    described_class.perform_now(booking.id, "created")
  end

  it 'logs 2 notifications on "cancelled" event' do
    expect(Rails.logger).to receive(:info)
      .with(/\[BookingNotificationJob\].*subject="\[mock\] booking_cancelled"/).twice
    allow(Rails.logger).to receive(:info).and_call_original
    described_class.perform_now(booking.id, "cancelled")
  end

  it "does not include raw email in log output (PII hash review fix I-B-1)" do
    captured = []
    allow(Rails.logger).to receive(:info) { |msg| captured << msg.to_s }
    described_class.perform_now(booking.id, "created")
    expect(captured.join("\n")).not_to include(booking.invitee_email)
    expect(captured.join("\n")).not_to include(booking.host.email)
    # 代わりに recipient_hash がある
    expect(captured.join("\n")).to match(/recipient_hash=[0-9a-f]{8}/)
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
