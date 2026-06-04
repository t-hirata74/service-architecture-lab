class User < ApplicationRecord
  has_many :owned_documents, class_name: "Document", foreign_key: :owner_id,
                             dependent: :destroy, inverse_of: :owner
  has_many :document_members, dependent: :destroy
  has_many :documents, through: :document_members
  has_many :operations, class_name: "Operation", foreign_key: :actor_id,
                        dependent: :destroy, inverse_of: :actor

  validates :name, presence: true
  validates :email, presence: true, uniqueness: true
end
