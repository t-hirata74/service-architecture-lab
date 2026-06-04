class DocumentMember < ApplicationRecord
  ROLES = %w[owner editor viewer].freeze

  belongs_to :document
  belongs_to :user

  validates :role, inclusion: { in: ROLES }
  validates :user_id, uniqueness: { scope: :document_id }

  # ADR 0004: viewer は op 拒否。owner / editor のみ書き込み可。
  def can_edit?
    role == "owner" || role == "editor"
  end
end
