# Phase 4-3: 認証は rodauth (Account) に寄せたため、has_secure_password / password_digest を撤去。
# Account とは shared PK (users.id == accounts.id) で 1:1 紐付く。
class User < ApplicationRecord
  belongs_to :account, foreign_key: :id, primary_key: :id, optional: true

  has_many :hosted_meetings, class_name: "Meeting", foreign_key: :host_id, dependent: :restrict_with_error
  has_many :participants, dependent: :destroy
  has_many :meeting_co_hosts, dependent: :destroy

  validates :email, presence: true, uniqueness: { case_sensitive: false }
  validates :display_name, presence: true
end
