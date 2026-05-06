class MeetingCoHost < ApplicationRecord
  belongs_to :meeting
  belongs_to :user
  belongs_to :granted_by_user, class_name: "User"

  validates :granted_at, presence: true
  validates :user_id, uniqueness: { scope: :meeting_id }

  before_validation :set_default_granted_at, on: :create

  private

  def set_default_granted_at
    self.granted_at ||= Time.current
  end
end
