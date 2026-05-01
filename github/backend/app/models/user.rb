class User < ApplicationRecord
  has_many :memberships, dependent: :destroy
  has_many :organizations, through: :memberships
  has_many :team_members, dependent: :destroy
  has_many :teams, through: :team_members
  has_many :repository_collaborators, dependent: :destroy

  validates :login, presence: true, uniqueness: true
  validates :email, presence: true, uniqueness: true
end
