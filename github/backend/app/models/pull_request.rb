class PullRequest < ApplicationRecord
  class InvalidTransition < StandardError; end

  belongs_to :repository
  belongs_to :author, class_name: "User"

  has_many :reviews, dependent: :destroy
  has_many :requested_reviewers, dependent: :destroy
  has_many :reviewers_requested, through: :requested_reviewers, source: :user
  has_many :comments, as: :commentable, dependent: :destroy

  enum :state, { open: 0, closed: 1, merged: 2 }, prefix: :state
  # `mergeable_state` のキーは Rails enum 制約上 `state` と衝突できないため `merged_state` / `closed_state` にしている。
  # GraphQL 側 (`MergeableStateEnum`) では MERGED / CLOSED にマップしてユーザに見える値は `state` と揃える。
  enum :mergeable_state, { mergeable: 0, conflict: 1, merged_state: 2, closed_state: 3 }, prefix: :mergeable

  # ADR 0004: PR の集約 check 状態は head_sha 配下の最新行から派生
  AGGREGATED_CHECK_STATES = %w[success failure pending none].freeze

  def commit_checks
    repository.commit_checks.where(head_sha: head_sha)
  end

  def aggregated_check_state
    states = commit_checks.map(&:state).map(&:to_s)
    return "none" if states.empty?

    if states.any? { |s| %w[failure error].include?(s) }
      "failure"
    elsif states.all? { |s| s == "success" }
      "success"
    else
      "pending"
    end
  end

  validates :title, presence: true
  validates :head_ref, presence: true
  validates :base_ref, presence: true
  validates :head_sha, presence: true
  validates :number, presence: true, uniqueness: { scope: :repository_id }
  validates :body, exclusion: { in: [nil] }

  def close!
    raise InvalidTransition, "already #{state}" unless state_open?

    update!(state: :closed, mergeable_state: :closed_state)
  end

  def merge!
    raise InvalidTransition, "must be open" unless state_open?
    raise InvalidTransition, "not mergeable (#{mergeable_state})" unless mergeable_mergeable?

    update!(state: :merged, mergeable_state: :merged_state)
  end
end
