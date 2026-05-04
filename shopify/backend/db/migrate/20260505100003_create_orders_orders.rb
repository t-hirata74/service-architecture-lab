# Phase 4: Order — checkout 確定後の注文。number は shop 単位のシーケンシャル (with_lock で採番)。
class CreateOrdersOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :orders_orders do |t|
      t.references :shop, null: false, foreign_key: { to_table: :core_shops }
      t.references :customer, null: false, foreign_key: { to_table: :core_users }
      t.bigint :number, null: false
      t.integer :status, null: false, default: 0
      t.bigint :total_cents, null: false, default: 0
      t.string :currency, null: false, default: "JPY", limit: 3
      t.timestamps
    end
    add_index :orders_orders, [ :shop_id, :number ], unique: true
    add_index :orders_orders, [ :shop_id, :status, :created_at ]
  end
end
