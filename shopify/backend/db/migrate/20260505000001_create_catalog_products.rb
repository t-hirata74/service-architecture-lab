# Phase 3: Product (catalog Engine)。ADR 0002 で全 tenant-scoped table に shop_id を持たせる。
class CreateCatalogProducts < ActiveRecord::Migration[8.1]
  def change
    create_table :catalog_products do |t|
      t.references :shop, null: false, foreign_key: { to_table: :core_shops }
      t.string :slug, null: false
      t.string :title, null: false
      t.text :description
      t.integer :status, null: false, default: 0
      t.timestamps
    end
    add_index :catalog_products, [ :shop_id, :slug ], unique: true
  end
end
