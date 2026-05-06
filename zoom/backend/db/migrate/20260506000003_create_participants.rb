# ADR 0001: participants.status は waiting / live / left の 3 値。
# UNIQUE(meeting_id, user_id) で「同じ会議に同じユーザは 1 行」を強制。
class CreateParticipants < ActiveRecord::Migration[8.1]
  def change
    create_table :participants do |t|
      t.references :meeting, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :status, null: false, default: "waiting"
      t.datetime :joined_at
      t.datetime :left_at
      t.timestamps
    end

    add_index :participants, [:meeting_id, :user_id], unique: true
    add_index :participants, [:meeting_id, :status]
  end
end
