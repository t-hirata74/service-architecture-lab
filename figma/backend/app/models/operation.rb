class Operation < ApplicationRecord
  OP_TYPES = %w[create update delete].freeze

  belongs_to :document
  belongs_to :actor, class_name: "User"

  validates :op_type, inclusion: { in: OP_TYPES }
  validates :seq, uniqueness: { scope: :document_id }

  # ADR 0002: append-only。既存行の UPDATE / DELETE を物理的に拒否 (zoom HostTransfer と同方針)。
  def readonly?
    !new_record?
  end
end
