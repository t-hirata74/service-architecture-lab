class Citation < ApplicationRecord
  belongs_to :answer
  belongs_to :source

  # ADR 0004: 同じ marker が同じ answer に重複永続化されないよう DB UNIQUE と整合.
  validates :marker, presence: true, length: { maximum: 64 },
                     uniqueness: { scope: :answer_id }
  validates :position, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
