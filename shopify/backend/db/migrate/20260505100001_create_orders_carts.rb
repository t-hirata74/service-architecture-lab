# Phase 4: Cart — checkout 前のショッピングカート。Customer (Core::User) に 1:1 で active な cart を持たせる。
class CreateOrdersCarts < ActiveRecord::Migration[8.1]
  def change
    create_table :orders_carts do |t|
      t.references :shop, null: false, foreign_key: { to_table: :core_shops }
      t.references :customer, null: false, foreign_key: { to_table: :core_users }
      t.integer :status, null: false, default: 0
      t.timestamps
    end
    add_index :orders_carts, [ :shop_id, :customer_id, :status ]
  end
end
