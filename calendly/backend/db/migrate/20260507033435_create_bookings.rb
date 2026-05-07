# ADR 0001 / 0002 / 0003: 予約の中核テーブル。
# - start_at / end_at は UTC 保存 (ADR 0003)
# - 閉開区間 [start_at, end_at) で overlap 判定 (ADR 0001)
# - 同時予約レース防止のための複合 index (ADR 0002)
# - status は pending / confirmed / cancelled / completed
class CreateBookings < ActiveRecord::Migration[8.1]
  STATUSES = %w[pending confirmed cancelled completed].freeze

  def change
    create_table :bookings do |t|
      t.references :event_type, null: false, foreign_key: true
      # event_type 経由でも辿れるが overlap 検査の direct query を高速化するため非正規化
      t.references :host, null: false, foreign_key: true

      t.datetime :start_at, null: false
      t.datetime :end_at, null: false

      # invitee は本リポでは mock 扱い (rodauth-rails で host 認証のみ実装、invitee は guest)
      t.string :invitee_email, null: false
      t.string :invitee_name
      # ADR 0003: invitee 表示用 TZ。booking 自体は UTC で保存し、invitee に返すときに変換する。
      t.string :invitee_tz_id, null: false

      t.string :status, null: false, default: "pending"

      t.timestamps
    end

    # ADR 0002: overlap 検索の複合 index。host 行 FOR UPDATE 後に高速 SELECT する。
    add_index :bookings, [ :host_id, :start_at, :end_at, :status ], name: "index_bookings_on_host_overlap"

    # ADR 0001: 閉開区間の前提を fixate
    add_check_constraint :bookings, "start_at < end_at", name: "bookings_start_before_end"
    add_check_constraint :bookings,
      "status IN ('pending','confirmed','cancelled','completed')",
      name: "bookings_status_enum"
  end
end
