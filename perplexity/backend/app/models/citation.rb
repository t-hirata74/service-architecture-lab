class Citation < ApplicationRecord
  belongs_to :answer
  belongs_to :source

  validates :marker, presence: true, length: { maximum: 64 }
  validates :position, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
