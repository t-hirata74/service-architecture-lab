class Membership < ApplicationRecord
  ROLES = %w[member admin].freeze

  belongs_to :user
  belongs_to :channel
  belongs_to :last_read_message, class_name: "Message", optional: true

  validates :role, inclusion: { in: ROLES }
  validates :user_id, uniqueness: { scope: :channel_id }
  validates :joined_at, presence: true

  before_validation :set_joined_at, on: :create

  # ADR 0002: 単調増加ガード — 既存値より大きい場合のみ更新
  def advance_read_cursor!(message_id, read_at: Time.current)
    return false if last_read_message_id && last_read_message_id >= message_id

    update!(last_read_message_id: message_id, last_read_at: read_at)
    true
  end

  private

  def set_joined_at
    self.joined_at ||= Time.current
  end
end
