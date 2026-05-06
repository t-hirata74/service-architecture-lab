class User < ApplicationRecord
  has_secure_password

  has_many :hosted_meetings, class_name: "Meeting", foreign_key: :host_id, dependent: :restrict_with_error
  has_many :participants, dependent: :destroy
  has_many :meeting_co_hosts, dependent: :destroy

  validates :email, presence: true, uniqueness: { case_sensitive: false }
  validates :display_name, presence: true
end
