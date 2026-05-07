# 予約可能なイベント種別 (例: "30 min interview", "1h consultation")。
# 1 host が複数の event_type を持つ。slug は public URL で使う。
class CreateEventTypes < ActiveRecord::Migration[8.1]
  def change
    create_table :event_types do |t|
      t.references :host, null: false, foreign_key: true
      t.string :slug, null: false
      t.string :title, null: false
      t.integer :duration_minutes, null: false

      # ADR 0001: buffer / min_notice / max_advance はスロット計算で頭尾を切る用。
      t.integer :before_buffer_minutes, null: false, default: 0
      t.integer :after_buffer_minutes, null: false, default: 0
      t.integer :min_notice_minutes, null: false, default: 60
      t.integer :max_advance_days, null: false, default: 60

      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :event_types, [ :host_id, :slug ], unique: true
  end
end
