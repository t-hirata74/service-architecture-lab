# Phase 2: User は accounts と共有 PK (ADR 0007 同形)。shop_id でテナント所属を表す (ADR 0002)。
class CreateCoreUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :core_users do |t|
      t.references :shop, null: false, foreign_key: { to_table: :core_shops }
      t.string :email, null: false
      t.timestamps
    end
    add_index :core_users, [ :shop_id, :email ], unique: true
  end
end
