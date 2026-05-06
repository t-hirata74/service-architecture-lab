# ADR 0003: recordings.meeting_id UNIQUE で「会議 1 件 = 録画 1 件」を保証。
# at-least-once な FinalizeRecordingJob が 2 回走っても upsert で 1 行のまま。
class Recording < ApplicationRecord
  belongs_to :meeting

  validates :meeting_id, uniqueness: true
  validates :mock_blob_path, presence: true
  validates :duration_seconds, numericality: { greater_than_or_equal_to: 0 }
  validates :finalized_at, presence: true
end
