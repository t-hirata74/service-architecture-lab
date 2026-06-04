class Document < ApplicationRecord
  belongs_to :owner, class_name: "User"
  has_many :document_members, dependent: :destroy
  has_many :members, through: :document_members, source: :user
  has_many :canvas_objects, dependent: :destroy
  has_many :operations, dependent: :destroy

  validates :name, presence: true

  # ADR 0002: 次の seq (server 権威の総順序) を with_lock で原子採番する。
  # OperationApplier から op INSERT と同一トランザクション内で呼ぶ (本実装は Phase 3)。
  def next_seq!
    with_lock do
      increment!(:version)
      version
    end
  end

  def member_role(user_id)
    document_members.where(user_id: user_id).pick(:role)
  end
end
