class TeamMember < ApplicationRecord
  belongs_to :team
  belongs_to :user

  enum :role, { member: 0, maintainer: 1, admin: 2 }, prefix: :team

  validates :user_id, uniqueness: { scope: :team_id }
end
