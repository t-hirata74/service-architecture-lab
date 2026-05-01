class Repository < ApplicationRecord
  belongs_to :organization
  has_many :team_repository_roles, dependent: :destroy
  has_many :teams, through: :team_repository_roles
  has_many :repository_collaborators, dependent: :destroy
  has_many :collaborators, through: :repository_collaborators, source: :user

  enum :visibility, { private_visibility: 0, internal_visibility: 1, public_visibility: 2 }

  validates :name, presence: true, uniqueness: { scope: :organization_id }
end
