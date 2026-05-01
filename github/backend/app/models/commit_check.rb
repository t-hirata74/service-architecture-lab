class CommitCheck < ApplicationRecord
  belongs_to :repository

  enum :state, { pending: 0, success: 1, failure: 2, error: 3 }, prefix: :state

  validates :head_sha, presence: true
  validates :name, presence: true

  # ADR 0004: ai-worker からの ingress は (repository, head_sha, name) で upsert
  def self.upsert_check!(repository:, head_sha:, name:, state:, output: nil, started_at: nil, completed_at: nil)
    record = find_or_initialize_by(repository_id: repository.id, head_sha: head_sha, name: name)
    record.assign_attributes(
      state: state,
      output: output,
      started_at: started_at || record.started_at || Time.current,
      completed_at: %w[success failure error].include?(state.to_s) ? (completed_at || Time.current) : nil
    )
    record.save!
    record
  end
end
