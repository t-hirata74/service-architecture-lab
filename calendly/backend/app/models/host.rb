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
  validates :default_tz_id, presence: true
  validate :default_tz_id_must_be_resolvable

  # review fix I-C-1: hosts.email と accounts.email は並列に UNIQUE 制約を持つ。
  # Host#update(email: ...) で drift しないよう、保存後に Account 側にも反映する。
  after_save :sync_email_to_account, if: :saved_change_to_email?

  private

  # ActiveSupport::TimeZone[] は IANA id / Rails friendly tz name 両方を解釈。
  # offset string ("+09:00") は nil を返すので拒否される。
  def default_tz_id_must_be_resolvable
    return if default_tz_id.blank?
    errors.add(:default_tz_id, "must be IANA tz id or Rails friendly tz name") if ActiveSupport::TimeZone[default_tz_id].nil?
  end

  def sync_email_to_account
    return unless account
    account.update_columns(email: email) unless account.email == email
  end
end
