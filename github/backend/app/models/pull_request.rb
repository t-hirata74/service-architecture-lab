class PullRequest < ApplicationRecord
  class InvalidTransition < StandardError; end

  belongs_to :repository
  belongs_to :author, class_name: "User"

  has_many :reviews, dependent: :destroy
  has_many :requested_reviewers, dependent: :destroy
  has_many :reviewers_requested, through: :requested_reviewers, source: :user
  has_many :comments, as: :commentable, dependent: :destroy

  enum :state, { open: 0, closed: 1, merged: 2 }, prefix: :state
  enum :mergeable_state, { mergeable: 0, conflict: 1, merged_state: 2, closed_state: 3 }, prefix: :mergeable

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
