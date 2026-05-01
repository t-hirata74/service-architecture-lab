class Issue < ApplicationRecord
  belongs_to :repository
  belongs_to :author, class_name: "User"

  has_many :issue_labels, dependent: :destroy
  has_many :labels, through: :issue_labels
  has_many :issue_assignees, dependent: :destroy
  has_many :assignees, through: :issue_assignees, source: :user
  has_many :comments, as: :commentable, dependent: :destroy

  enum :state, { open: 0, closed: 1 }, prefix: :state

  validates :title, presence: true
  validates :number, presence: true, uniqueness: { scope: :repository_id }
  validates :body, exclusion: { in: [nil] }

  def close!
    return false if state_closed?

    update!(state: :closed)
  end

  def reopen!
    return false if state_open?

    update!(state: :open)
  end
end
