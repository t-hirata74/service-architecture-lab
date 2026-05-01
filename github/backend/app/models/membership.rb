class Membership < ApplicationRecord
  belongs_to :organization
  belongs_to :user

  # Org base role: outside_collaborator < member < admin
  enum :role, { outside_collaborator: 0, member: 1, admin: 2 }, prefix: :org

  validates :user_id, uniqueness: { scope: :organization_id }
end
