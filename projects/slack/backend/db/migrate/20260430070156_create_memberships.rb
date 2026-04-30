class CreateMemberships < ActiveRecord::Migration[8.0]
  def change
    create_table :memberships do |t|
      t.references :user, null: false, foreign_key: true, type: :bigint
      t.references :channel, null: false, foreign_key: true, type: :bigint
      t.string :role, null: false, default: "member"
      t.datetime :joined_at, null: false, precision: 6

      # ADR 0002: 既読 cursor 方式
      t.bigint :last_read_message_id
      t.datetime :last_read_at, precision: 6

      t.timestamps precision: 6

      t.index [:user_id, :channel_id], unique: true
    end
  end
end
