# Phase 3: InventoryLevel — (variant, location) ごとの在庫数 truth (ADR 0003)。
# `UPDATE inventory_levels SET on_hand = on_hand - :q WHERE on_hand >= :q` で減算する。
# UNIQUE (variant_id, location_id) で同一組合せの行を 1 つに保つ。
class CreateInventoryLevels < ActiveRecord::Migration[8.1]
  def change
    create_table :inventory_levels do |t|
      t.references :shop, null: false, foreign_key: { to_table: :core_shops }
      t.references :variant, null: false, foreign_key: { to_table: :catalog_variants }
      t.references :location, null: false, foreign_key: { to_table: :inventory_locations }
      t.integer :on_hand, null: false, default: 0
      t.timestamps
    end
    add_index :inventory_levels, [ :variant_id, :location_id ], unique: true
  end
end
