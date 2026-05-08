# ADR 0001 / 0002 / 0003: 予約の中核モデル。
# - start_at / end_at は UTC datetime (ADR 0003)
# - 閉開区間 [start_at, end_at) (ADR 0001)
# - 同時予約レース防止は Bookings::CreateService が担う (ADR 0002)。本モデルは状態と scope だけ持つ。
class Booking < ApplicationRecord
  STATUSES = %w[pending confirmed cancelled completed].freeze
  ACTIVE_STATUSES = %w[pending confirmed].freeze  # overlap 検査の対象

  belongs_to :event_type
  belongs_to :host

  validates :start_at, :end_at, :invitee_email, :invitee_tz_id, presence: true
  validates :status, inclusion: { in: STATUSES }
  validate :invitee_tz_id_must_be_resolvable
  validate :start_before_end

  STATUSES.each do |s|
    define_method("#{s}?") { status == s }
  end

  # ADR 0002: overlap 検索の中核 scope。confirmed / pending のみ衝突対象、cancelled は無視。
  scope :active, -> { where(status: ACTIVE_STATUSES) }
  scope :overlapping, ->(host_id, from, to) {
    active.where(host_id: host_id).where("start_at < ? AND end_at > ?", to, from)
  }

  # キャンセル: 状態遷移を冪等に (zoom 同形)。同 host が同枠を別人に再予約可能。
  def cancel!
    return if cancelled?
    raise InvalidTransition, "cannot cancel booking with status=#{status}" unless ACTIVE_STATUSES.include?(status)
    transaction do
      update!(status: "cancelled")
      BookingNotificationJob.perform_later(id, "cancelled")
    end
  end

  class InvalidTransition < StandardError; end

  private

  def start_before_end
    return if start_at.nil? || end_at.nil?
    errors.add(:end_at, "must be after start_at") if end_at <= start_at
  end

  def invitee_tz_id_must_be_resolvable
    return if invitee_tz_id.blank?
    errors.add(:invitee_tz_id, "must be IANA tz id or Rails friendly tz name") if ActiveSupport::TimeZone[invitee_tz_id].nil?
  end
end
