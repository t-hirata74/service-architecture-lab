class RepositoryCollaborator < ApplicationRecord
  belongs_to :repository
  belongs_to :user

  enum :role, { read: 0, triage: 1, write: 2, maintain: 3, admin: 4 }, prefix: :repo

  validates :user_id, uniqueness: { scope: :repository_id }
end
