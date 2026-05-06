# ADR 0003: recordings.meeting_id UNIQUE で「会議 1 件 = 録画 1 件」を保証。
# at-least-once な FinalizeRecordingJob が 2 回走っても upsert で 1 行のまま。
class CreateRecordings < ActiveRecord::Migration[8.1]
  def change
    create_table :recordings do |t|
      t.references :meeting, null: false, foreign_key: true, index: { unique: true }
      t.string :mock_blob_path, null: false # 実 blob は持たず path 文字列のみ (policy: WebRTC は別領域)
      t.integer :duration_seconds, null: false, default: 0
      t.datetime :finalized_at, null: false
      t.timestamps
    end
  end
end
