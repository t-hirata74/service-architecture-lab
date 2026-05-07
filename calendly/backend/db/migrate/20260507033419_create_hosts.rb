# ADR 0003: ホストの default_tz_id は IANA tz database id ("Asia/Tokyo" 等) を保存する。
# offset string ("+09:00") は DST を表現できないため不可。
class CreateHosts < ActiveRecord::Migration[8.1]
  def change
    create_table :hosts do |t|
      t.string :email, null: false
      t.string :name, null: false
      t.string :default_tz_id, null: false, default: "UTC"
      t.timestamps
    end
    add_index :hosts, :email, unique: true
  end
end
