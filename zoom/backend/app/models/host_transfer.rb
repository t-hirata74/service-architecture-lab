# ADR 0002: ホスト譲渡履歴は append-only。
# 永続化後の UPDATE / DELETE はアプリ層で禁止する。`updated_at` カラムを持たないことが
# DB スキーマレベルの append-only シグナル。
class HostTransfer < ApplicationRecord
  REASONS = %w[voluntary host_left forced].freeze

  belongs_to :meeting
  belongs_to :from_user, class_name: "User"
  belongs_to :to_user, class_name: "User"

  validates :reason, inclusion: { in: REASONS }
  validates :transferred_at, presence: true
  validate :from_and_to_must_differ

  def readonly?
    persisted?
  end

  before_destroy :forbid_destroy

  private

  def from_and_to_must_differ
    return if from_user_id.nil? || to_user_id.nil?
    errors.add(:to_user_id, "must differ from from_user_id") if from_user_id == to_user_id
  end

  def forbid_destroy
    raise ActiveRecord::ReadOnlyRecord, "host_transfers are append-only (ADR 0002)"
  end
end
