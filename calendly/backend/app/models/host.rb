# 予約を受ける側のユーザー (host)。invitee はモデルとして持たず、guest として
# bookings.invitee_email / invitee_tz_id 等で扱う (rodauth-rails で host 認証だけ実装する想定)。
class Host < ApplicationRecord
  # Phase 4-3: 認証は rodauth (Account) に寄せる。Account とは shared PK (hosts.id == accounts.id)。
  belongs_to :account, foreign_key: :id, primary_key: :id, optional: true

  has_many :event_types, dependent: :destroy
  has_many :availability_rules, dependent: :destroy
  has_many :busy_periods, dependent: :destroy
  has_many :bookings, dependent: :restrict_with_error

  validates :email, presence: true, uniqueness: { case_sensitive: false }
  validates :name, presence: true
  # ADR 0003: IANA tz database id ("Asia/Tokyo" 等)。offset string ("+09:00") は不可。
  validates :default_tz_id, presence: true, inclusion: { in: ->(_) { ActiveSupport::TimeZone::MAPPING.values } }
end
