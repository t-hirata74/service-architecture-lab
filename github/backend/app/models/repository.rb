class Repository < ApplicationRecord
  belongs_to :organization
  has_many :team_repository_roles, dependent: :destroy
  has_many :teams, through: :team_repository_roles
  has_many :repository_collaborators, dependent: :destroy
  has_many :collaborators, through: :repository_collaborators, source: :user
  has_many :issues, dependent: :destroy
  has_many :pull_requests, dependent: :destroy
  has_many :labels, dependent: :destroy
  has_many :commit_checks, dependent: :destroy
  has_one :repository_issue_number, dependent: :destroy

  enum :visibility, { private_visibility: 0, internal_visibility: 1, public_visibility: 2 }

  validates :name, presence: true, uniqueness: { scope: :organization_id }
end
