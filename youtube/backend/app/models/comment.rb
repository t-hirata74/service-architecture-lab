class Comment < ApplicationRecord
  belongs_to :video
  belongs_to :user
  belongs_to :parent, class_name: "Comment", optional: true
  has_many :replies, class_name: "Comment", foreign_key: :parent_id, dependent: :destroy

  validates :body, presence: true, length: { maximum: 2_000 }
  validate :enforce_one_level_thread

  scope :top_level, -> { where(parent_id: nil).order(created_at: :asc) }

  private

  # スレッドは 1 段までに限定する (CLAUDE.md スコープ: ネスト深部は学習価値が薄い)
  def enforce_one_level_thread
    return if parent_id.blank?
    errors.add(:parent_id, "must reference a top-level comment") if parent&.parent_id.present?
  end
end
