# ADR 0003: recurring availability を RRULE 文字列のまま保存する (lazy 展開)。
# 「壁時計 (start_time_of_day / end_time_of_day) + tz_id」で保存し、UTC 保存はしない。
class CreateAvailabilityRules < ActiveRecord::Migration[8.1]
  def change
    create_table :availability_rules do |t|
      t.references :host, null: false, foreign_key: true
      # null = host グローバル / 値あり = event_type 固有の上書き
      t.references :event_type, null: true, foreign_key: true

      # 例: "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR"
      t.string :rrule, null: false

      # 壁時計。tz_id と合わせてその TZ の 09:00-17:00 を意味する。
      t.time :start_time_of_day, null: false
      t.time :end_time_of_day, null: false

      # IANA tz database id (例: "Asia/Tokyo")。offset string は DST を表現できないため不可。
      t.string :tz_id, null: false

      # ルールの有効期間 (null は片側無限)
      t.date :effective_from
      t.date :effective_until

      t.timestamps
    end
    add_index :availability_rules, [ :host_id, :event_type_id, :effective_from ], name: "index_availability_rules_on_host_event_effective"
  end
end
