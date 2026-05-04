# Phase 3: Location (warehouse / store)。Shop 単位で複数持てる前提のテーブル。
# 本 MVP は location 1 件運用だが、ADR 0003 で「複数 location アロケーションは派生 ADR」と切り出している。
class CreateInventoryLocations < ActiveRecord::Migration[8.1]
  def change
    create_table :inventory_locations do |t|
      t.references :shop, null: false, foreign_key: { to_table: :core_shops }
      t.string :name, null: false
      t.string :kind, null: false, default: "warehouse"
      t.timestamps
    end
    add_index :inventory_locations, [ :shop_id, :name ], unique: true
  end
end
