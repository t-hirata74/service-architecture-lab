class TeamRepositoryRole < ApplicationRecord
  belongs_to :team
  belongs_to :repository

  # ADR 0002: Repository に対する role 階層
  # read < triage < write < maintain < admin
  enum :role, { read: 0, triage: 1, write: 2, maintain: 3, admin: 4 }, prefix: :repo

  validates :repository_id, uniqueness: { scope: :team_id }
end
