class RequestedReviewer < ApplicationRecord
  belongs_to :pull_request
  belongs_to :user

  validates :user_id, uniqueness: { scope: :pull_request_id }
end
