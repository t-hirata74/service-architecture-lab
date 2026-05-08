require "digest"

# 予約作成 / キャンセル時の通知ジョブ。
# 本リポでは外部 SaaS (SendGrid 等) を使わない方針 (policy)。
# 単に Rails.logger.info で「送信したことにする」mock 実装。
#
# at-least-once 前提 (zoom と同形)。冪等性は payload を idempotency_key として
# DB-backed dedupe する余地ありだが MVP ではログだけ。
#
# review fix I-B-1: PII (email) は平文ではなく SHA256 truncate でログに出す。
class BookingNotificationJob < ApplicationJob
  queue_as :default

  # ArgumentError は呼び出し側のバグなのでリトライしない (discard_on は ActiveJob 標準)。
  discard_on ArgumentError
  retry_on StandardError, attempts: 3, wait: :polynomially_longer

  # subject にも invitee_email を含めない (truncate hash で出す)。
  EVENTS = {
    "created"   => { host_subject: "new_booking", invitee_subject: "booking_confirmed" },
    "cancelled" => { host_subject: "booking_cancelled", invitee_subject: "booking_cancelled" },
  }.freeze

  def perform(booking_id, event)
    booking = Booking.find_by(id: booking_id)
    return unless booking  # 削除済みは冪等に終了 (zoom と同形)

    config = EVENTS[event]
    raise ArgumentError, "unknown event=#{event}" if config.nil?

    log_send(booking, recipient: booking.host.email,
                      subject: "[mock] #{config[:host_subject]}")
    log_send(booking, recipient: booking.invitee_email,
                      subject: "[mock] #{config[:invitee_subject]}")
  end

  private

  def log_send(booking, recipient:, subject:)
    # PII を直接ログに出さない。SHA256 hex の先頭 8 文字で代替し、
    # トラブルシュート時に「同じ宛先か」を比較できる程度に保つ。
    Rails.logger.info(
      "[BookingNotificationJob] booking_id=#{booking.id} " \
      "recipient_hash=#{Digest::SHA256.hexdigest(recipient.to_s)[0, 8]} " \
      "subject=#{subject.inspect}"
    )
  end
end
