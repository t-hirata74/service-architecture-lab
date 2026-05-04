class CreateOrdersCartItems < ActiveRecord::Migration[8.1]
  def change
    create_table :orders_cart_items do |t|
      t.references :shop, null: false, foreign_key: { to_table: :core_shops }
      t.references :cart, null: false, foreign_key: { to_table: :orders_carts }
      t.references :variant, null: false, foreign_key: { to_table: :catalog_variants }
      t.integer :quantity, null: false, default: 1
      t.timestamps
    end
    add_index :orders_cart_items, [ :cart_id, :variant_id ], unique: true
  end
end
