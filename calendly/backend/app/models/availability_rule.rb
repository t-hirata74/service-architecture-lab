# ADR 0003: recurring availability。RRULE 文字列のまま保存し、
# 取得時に Availability::RruleExpansion で展開する (lazy 展開)。
# 「壁時計 + tz_id」で保存し、UTC 保存はしない (DST 跨ぎで壁時計が動かない)。
class AvailabilityRule < ApplicationRecord
  belongs_to :host
  belongs_to :event_type, optional: true  # null = host グローバル

  validates :rrule, presence: true
  validates :start_time_of_day, :end_time_of_day, presence: true
  validates :tz_id, presence: true
  validate :tz_id_must_be_resolvable

  validate :end_after_start
  validate :rrule_supported

  # ADR 0003 規律 2: 本リポは RRULE フル仕様を実装しない。
  # MVP は FREQ=WEEKLY;BYDAY=... のサブセットだけ。INTERVAL/COUNT/UNTIL は派生 ADR で。
  SUPPORTED_FREQ = %w[WEEKLY].freeze

  private

  def end_after_start
    return if start_time_of_day.nil? || end_time_of_day.nil?
    if end_time_of_day <= start_time_of_day
      errors.add(:end_time_of_day, "must be after start_time_of_day")
    end
  end

  def tz_id_must_be_resolvable
    return if tz_id.blank?
    errors.add(:tz_id, "must be IANA tz id or Rails friendly tz name") if ActiveSupport::TimeZone[tz_id].nil?
  end

  def rrule_supported
    return if rrule.blank?
    pairs = rrule.split(";").map { |kv| kv.split("=", 2) }.to_h
    unless SUPPORTED_FREQ.include?(pairs["FREQ"])
      errors.add(:rrule, "FREQ=#{pairs["FREQ"]} is not supported (MVP: #{SUPPORTED_FREQ.join("/")})")
    end
  end
end
