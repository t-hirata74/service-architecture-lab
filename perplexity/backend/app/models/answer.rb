class Answer < ApplicationRecord
  STATUSES = %w[streaming completed failed].freeze

  belongs_to :query
  has_many :citations, -> { order(position: :asc) }, dependent: :destroy

  validates :body, presence: true
  validates :status, inclusion: { in: STATUSES }

  STATUSES.each do |s|
    define_method("#{s}?") { status == s }
  end
end
