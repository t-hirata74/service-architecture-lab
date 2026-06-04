class CanvasObject < ApplicationRecord
  KINDS = %w[rect ellipse text].freeze

  belongs_to :document

  validates :kind, inclusion: { in: KINDS }
  validates :shape_id, uniqueness: { scope: :document_id }

  # snapshot は生きているオブジェクトだけ返す (deleted は props["deleted"] の LWW 写像、ADR 0001/0002)。
  scope :alive, -> { where(deleted: false) }
end
