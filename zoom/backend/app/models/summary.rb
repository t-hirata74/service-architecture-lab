# ADR 0003: summaries.meeting_id UNIQUE が冪等保証の核。
# at-least-once な SummarizeMeetingJob が 2 回 upsert しても 1 行で済む。
# input_hash は ai-worker の deterministic mock の入力フィンガープリント。
class Summary < ApplicationRecord
  belongs_to :meeting

  validates :meeting_id, uniqueness: true
  validates :body, presence: true
  validates :input_hash, presence: true
  validates :generated_at, presence: true
end
