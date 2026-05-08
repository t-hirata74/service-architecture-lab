# 予約可能なイベント種別 (例: "30 min interview")。1 host が複数持つ。
# slug は public URL (`/<host>/<slug>`) で使う。
class EventType < ApplicationRecord
  belongs_to :host
  has_many :availability_rules, dependent: :destroy
  has_many :bookings, dependent: :restrict_with_error

  validates :slug, presence: true,
    format: { with: /\A[a-z0-9-]+\z/, message: "must be kebab-case lowercase" },
    uniqueness: { scope: :host_id }
  validates :title, presence: true
  validates :duration_minutes, numericality: { greater_than: 0, only_integer: true }
  validates :before_buffer_minutes, :after_buffer_minutes, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :min_notice_minutes, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :max_advance_days, numericality: { greater_than: 0, only_integer: true }

  scope :active, -> { where(active: true) }
end
