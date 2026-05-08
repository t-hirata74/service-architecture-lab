module Bookings
  # ADR 0002: 同時予約レース防止 — MySQL における EXCLUDE 排他制約代替。
  # `host` 行を `FOR UPDATE` で lock → overlap 検査 → INSERT までを 1 transaction で行う。
  # 同 host への並行 INSERT が直列化され、後発は BookingConflict で 409 に落ちる。
  class CreateService
    class BookingConflict < StandardError; end
    class NotAvailable < StandardError; end  # availability_rules に該当しない時間帯

    def initialize(event_type:, start_at:, invitee_email:, invitee_tz_id:, invitee_name: nil)
      @event_type = event_type
      @start_at = start_at.utc
      @end_at = @start_at + event_type.duration_minutes.minutes
      @invitee_email = invitee_email
      @invitee_name = invitee_name
      @invitee_tz_id = invitee_tz_id
    end

    def call
      Booking.transaction do
        host = Host.lock("FOR UPDATE").find(@event_type.host_id)

        if Booking.overlapping(host.id, @start_at, @end_at).exists?
          raise BookingConflict, "host=#{host.id} window=[#{@start_at}, #{@end_at}) overlaps existing booking"
        end

        if @event_type.host.busy_periods.overlapping(@start_at, @end_at).exists?
          raise BookingConflict, "host=#{host.id} window overlaps busy_period"
        end

        booking = Booking.create!(
          event_type_id: @event_type.id,
          host_id: host.id,
          start_at: @start_at,
          end_at: @end_at,
          invitee_email: @invitee_email,
          invitee_name: @invitee_name,
          invitee_tz_id: @invitee_tz_id,
          status: "confirmed"
        )
        # ApplicationJob の enqueue_after_transaction_commit = true により
        # transaction commit 後に worker が pickup する (orphan job 防止 / operating-patterns §21)。
        BookingNotificationJob.perform_later(booking.id, "created")
        booking
      end
    end
  end
end
