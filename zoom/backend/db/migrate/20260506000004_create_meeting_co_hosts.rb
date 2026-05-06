# ADR 0002: co-host は中間テーブルで N 件管理。granted_by_user_id は監査用の指名者記録。
class CreateMeetingCoHosts < ActiveRecord::Migration[8.1]
  def change
    create_table :meeting_co_hosts do |t|
      t.references :meeting, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :granted_by_user, null: false, foreign_key: { to_table: :users }
      t.datetime :granted_at, null: false
      t.timestamps
    end

    add_index :meeting_co_hosts, [:meeting_id, :user_id], unique: true
  end
end
