class Team < ApplicationRecord
  belongs_to :organization
  has_many :team_members, dependent: :destroy
  has_many :users, through: :team_members
  has_many :team_repository_roles, dependent: :destroy
  has_many :repositories, through: :team_repository_roles

  validates :slug, presence: true, uniqueness: { scope: :organization_id }
end
