class Channel < ApplicationRecord
  KINDS = %w[public private dm].freeze

  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships
  has_many :messages, dependent: :destroy

  validates :name, presence: true, length: { maximum: 80 }
  validates :kind, inclusion: { in: KINDS }
  validates :name, uniqueness: { scope: :kind }
end
