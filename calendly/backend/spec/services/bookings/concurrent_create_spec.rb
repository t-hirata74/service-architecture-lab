require "rails_helper"

# ADR 0002 fixate: 100 並行 thread が同じスロットを取りに行ったとき、
# 「**唯一の予約だけが成立する**」不変条件を確認する。shopify ADR 0003 の concurrent_deduct_spec と同形。
# transactional fixtures を切らないと FOR UPDATE が直列化されないため `use_transactional_fixtures: false`
# を spec に明示する。
RSpec.describe Bookings::CreateService, "concurrent INSERT", use_transactional_fixtures: false do
  let(:host) { Host.create!(email: "concurrent-host@example.com", name: "Host", default_tz_id: "Asia/Tokyo") }
  let(:event_type) do
    EventType.create!(host: host, slug: "interview", title: "Concurrent Test",
                      duration_minutes: 60, before_buffer_minutes: 0, after_buffer_minutes: 0,
                      min_notice_minutes: 0, max_advance_days: 365, active: true)
  end

  before { host; event_type }

  after do
    Booking.delete_all
    EventType.delete_all
    Host.delete_all
  end

  it "100 並行 thread のうち 1 件だけが confirmed、残り 99 件は BookingConflict" do
    threads = []
    successes = Concurrent::AtomicFixnum.new(0)
    conflicts = Concurrent::AtomicFixnum.new(0)
    barrier = Concurrent::CyclicBarrier.new(100)

    100.times do |i|
      threads << Thread.new do
        barrier.wait
        Bookings::CreateService.new(
          event_type: event_type,
          start_at: Time.utc(2026, 6, 1, 9, 0),
          invitee_email: "invitee#{i}@example.com",
          invitee_tz_id: "Asia/Tokyo"
        ).call
        successes.increment
      rescue Bookings::CreateService::BookingConflict
        conflicts.increment
      ensure
        ActiveRecord::Base.connection_pool.release_connection
      end
    end
    threads.each(&:join)

    expect(successes.value).to eq(1)
    expect(conflicts.value).to eq(99)
    expect(Booking.where(host_id: host.id, status: "confirmed").count).to eq(1)
  end
end
