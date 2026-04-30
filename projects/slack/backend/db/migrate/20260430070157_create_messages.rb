class CreateMessages < ActiveRecord::Migration[8.0]
  def change
    create_table :messages do |t|
      t.references :channel, null: false, foreign_key: true, type: :bigint
      t.references :user, null: false, foreign_key: true, type: :bigint
      t.references :parent_message, foreign_key: { to_table: :messages }, type: :bigint
      t.text :body, null: false
      t.datetime :edited_at, precision: 6
      t.datetime :deleted_at, precision: 6
      t.timestamps precision: 6

      # ADR 0002: チャンネル内タイムライン取得用
      t.index [:channel_id, :id]
    end
  end
end
