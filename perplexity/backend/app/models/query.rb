class Query < ApplicationRecord
  STATUSES = %w[pending streaming completed failed].freeze

  belongs_to :user
  has_many :query_retrievals, -> { order(rank: :asc) }, dependent: :destroy
  has_one :answer, dependent: :destroy

  validates :text, presence: true
  validates :status, inclusion: { in: STATUSES }

  STATUSES.each do |s|
    define_method("#{s}?") { status == s }
  end

  def mark!(new_status)
    raise ArgumentError, "invalid status: #{new_status}" unless STATUSES.include?(new_status.to_s)
    update!(status: new_status.to_s)
  end
end
