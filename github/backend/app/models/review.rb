class Review < ApplicationRecord
  belongs_to :pull_request
  belongs_to :reviewer, class_name: "User"

  enum :state, { commented: 0, approved: 1, changes_requested: 2 }, prefix: :review

  validates :body, exclusion: { in: [nil] }
end
