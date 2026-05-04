# Phase 3: StockMovement — append-only ledger (ADR 0003)。
# `SUM(stock_movements.delta) + initial == inventory_levels.on_hand` の不変条件を持つ。
# `updated_at` は持たず、created_at のみ。Model 側で readonly? を override して update を拒否する。
class CreateInventoryStockMovements < ActiveRecord::Migration[8.1]
  def change
    create_table :inventory_stock_movements do |t|
      t.references :shop, null: false, foreign_key: { to_table: :core_shops }
      t.references :variant, null: false, foreign_key: { to_table: :catalog_variants }
      t.references :location, null: false, foreign_key: { to_table: :inventory_locations }
      t.integer :delta, null: false
      t.string :reason, null: false
      t.string :source_type
      t.bigint :source_id
      t.datetime :created_at, null: false, default: -> { "CURRENT_TIMESTAMP(6)" }
    end
    add_index :inventory_stock_movements, [ :variant_id, :location_id, :created_at ],
              name: "idx_stock_movements_lookup"
    add_index :inventory_stock_movements, [ :source_type, :source_id ]
  end
end
