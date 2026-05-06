# ADR 0003: summaries.meeting_id UNIQUE が冪等保証の核。
# at-least-once な SummarizeMeetingJob が 2 回 upsert しても 1 行で済む。
# input_hash は ai-worker が deterministic mock を返すための入力フィンガープリント。
class CreateSummaries < ActiveRecord::Migration[8.1]
  def change
    create_table :summaries do |t|
      t.references :meeting, null: false, foreign_key: true, index: { unique: true }
      t.text :body, null: false
      t.string :input_hash, null: false
      t.datetime :generated_at, null: false
      t.timestamps
    end
  end
end
