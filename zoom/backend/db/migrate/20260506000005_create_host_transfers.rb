# ADR 0002: ホスト譲渡履歴は append-only。UPDATE / DELETE しない方針を spec で fixate する。
# updated_at は持たない (生成のみ、更新は無い) — created_at = transferred_at として運用も検討したが、
# 概念分離のため transferred_at を明示。
class CreateHostTransfers < ActiveRecord::Migration[8.1]
  def change
    create_table :host_transfers do |t|
      t.references :meeting, null: false, foreign_key: true
      t.references :from_user, null: false, foreign_key: { to_table: :users }
      t.references :to_user, null: false, foreign_key: { to_table: :users }
      t.datetime :transferred_at, null: false
      t.string :reason, null: false # ENUM 相当: voluntary / host_left / forced
      t.datetime :created_at, null: false
    end

    add_index :host_transfers, [:meeting_id, :transferred_at]
  end
end
