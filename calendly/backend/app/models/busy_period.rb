# 外部カレンダー (Google / Outlook 等) から取り込む host の既存予定を表す。
# 本リポではモック扱い。bookings と並んで availability merge の入力 (ADR 0001)。
# UTC 保存。閉開区間 [start_at, end_at)。
class BusyPeriod < ApplicationRecord
  SOURCES = %w[manual google_calendar outlook].freeze

  belongs_to :host

  validates :start_at, :end_at, presence: true
  validates :source, inclusion: { in: SOURCES }
  validate :start_before_end

  scope :overlapping, ->(from, to) { where("start_at < ? AND end_at > ?", to, from) }

  private

  def start_before_end
    return if start_at.nil? || end_at.nil?
    errors.add(:end_at, "must be after start_at") if end_at <= start_at
  end
end
