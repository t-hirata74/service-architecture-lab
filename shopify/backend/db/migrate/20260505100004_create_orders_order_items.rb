# Phase 4: OrderItem — checkout 時点の価格を unit_price_cents として封印 (履歴整合性)。
class CreateOrdersOrderItems < ActiveRecord::Migration[8.1]
  def change
    create_table :orders_order_items do |t|
      t.references :shop, null: false, foreign_key: { to_table: :core_shops }
      t.references :order, null: false, foreign_key: { to_table: :orders_orders }
      t.references :variant, null: false, foreign_key: { to_table: :catalog_variants }
      t.integer :quantity, null: false
      t.bigint :unit_price_cents, null: false
      t.string :currency, null: false, limit: 3
      t.timestamps
    end
    add_index :orders_order_items, [ :order_id, :variant_id ]
  end
end
