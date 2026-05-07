# 外部カレンダー (Google / Outlook 等) から取り込む host の既存予定を表す。
# 本リポではモック扱い。bookings と並んで availability merge の入力 (ADR 0001)。
# UTC 保存。閉開区間 [start_at, end_at)。
class CreateBusyPeriods < ActiveRecord::Migration[8.1]
  def change
    create_table :busy_periods do |t|
      t.references :host, null: false, foreign_key: true
      t.datetime :start_at, null: false
      t.datetime :end_at, null: false
      t.string :source, null: false, default: "manual"  # manual / google_calendar / outlook (mock)
      t.string :external_id  # 元カレンダーの event id (重複取込防止)
      t.timestamps
    end
    add_index :busy_periods, [ :host_id, :start_at, :end_at ]
    add_check_constraint :busy_periods, "start_at < end_at", name: "busy_periods_start_before_end"
  end
end
