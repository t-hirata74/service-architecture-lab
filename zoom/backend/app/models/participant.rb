class Participant < ApplicationRecord
  STATUSES = %w[waiting live left].freeze

  belongs_to :meeting
  belongs_to :user

  validates :status, inclusion: { in: STATUSES }
  validates :user_id, uniqueness: { scope: :meeting_id }

  STATUSES.each do |s|
    define_method("#{s}?") { status == s }
  end

  scope :waiting_for_admit, -> { where(status: "waiting") }
  scope :live_now, -> { where(status: "live") }

  # ADR 0001 / 0002: ホストか co-host が呼ぶ admit は controller / service 側で権限チェック。
  # モデル側は遷移制約のみ守る。
  def admit!(at: Time.current)
    raise "cannot admit non-waiting participant" unless waiting?
    update!(status: "live", joined_at: at)
  end

  def leave!(at: Time.current)
    raise "cannot leave non-live participant" unless live?
    update!(status: "left", left_at: at)
  end
end
