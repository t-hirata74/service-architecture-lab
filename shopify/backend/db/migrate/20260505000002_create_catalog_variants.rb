# Phase 3: Variant。1 Product 配下の SKU 単位。shop_id は product 経由で継承するが、
# index 効率と将来の sharding を考えて denormalize して保持する (ADR 0002)。
class CreateCatalogVariants < ActiveRecord::Migration[8.1]
  def change
    create_table :catalog_variants do |t|
      t.references :shop, null: false, foreign_key: { to_table: :core_shops }
      t.references :product, null: false, foreign_key: { to_table: :catalog_products }
      t.string :sku, null: false
      t.integer :price_cents, null: false, default: 0
      t.string :currency, null: false, default: "JPY", limit: 3
      t.timestamps
    end
    add_index :catalog_variants, [ :shop_id, :sku ], unique: true
  end
end
