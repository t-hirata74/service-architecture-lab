class Message < ApplicationRecord
  belongs_to :channel
  belongs_to :user, optional: true
  belongs_to :parent_message, class_name: "Message", optional: true

  has_many :replies, class_name: "Message", foreign_key: :parent_message_id, dependent: :destroy

  validates :body, presence: true, length: { maximum: 8000 }

  scope :active, -> { where(deleted_at: nil) }

  def soft_delete!
    update!(deleted_at: Time.current)
  end

  def edited?
    edited_at.present?
  end
end
