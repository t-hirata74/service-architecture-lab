# 予約作成 / キャンセル時の通知ジョブ。
# 本リポでは外部 SaaS (SendGrid 等) を使わない方針 (policy)。
# 単に Rails.logger.info で「送信したことにする」mock 実装。
#
# at-least-once 前提 (zoom と同形)。冪等性は payload を idempotency_key として
# DB-backed dedupe する余地ありだが MVP ではログだけ。
class BookingNotificationJob < ApplicationJob
  queue_as :default

  # ArgumentError は呼び出し側のバグなのでリトライしない (discard_on は ActiveJob 標準)。
  discard_on ArgumentError
  retry_on StandardError, attempts: 3, wait: :polynomially_longer

  def perform(booking_id, event)
    booking = Booking.find_by(id: booking_id)
    return unless booking  # 削除済みは冪等に終了 (zoom と同形)

    case event
    when "created"
      log_send(booking, recipient: booking.host.email,
                        subject: "[mock] New booking from #{booking.invitee_email}")
      log_send(booking, recipient: booking.invitee_email,
                        subject: "[mock] Your booking is confirmed")
    when "cancelled"
      log_send(booking, recipient: booking.host.email,
                        subject: "[mock] Booking cancelled by #{booking.invitee_email}")
      log_send(booking, recipient: booking.invitee_email,
                        subject: "[mock] Your booking has been cancelled")
    else
      raise ArgumentError, "unknown event=#{event}"
    end
  end

  private

  def log_send(booking, recipient:, subject:)
    Rails.logger.info(
      "[BookingNotificationJob] booking_id=#{booking.id} recipient=#{recipient} subject=#{subject.inspect}"
    )
  end
end
