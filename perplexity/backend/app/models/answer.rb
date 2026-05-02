class Answer < ApplicationRecord
  STATUSES = %w[streaming completed failed].freeze

  belongs_to :query
  has_many :citations, -> { order(position: :asc) }, dependent: :destroy

  # body の上限はカラム上は MEDIUMTEXT (16MB) だが、アプリ層で 64KB でガード.
  # Phase 4 で SSE が長文を流す場合はこの上限を再検討する.
  MAX_BODY_LENGTH = 65_536

  validates :body, presence: true, length: { maximum: MAX_BODY_LENGTH }
  validates :status, inclusion: { in: STATUSES }

  STATUSES.each do |s|
    define_method("#{s}?") { status == s }
  end
end
