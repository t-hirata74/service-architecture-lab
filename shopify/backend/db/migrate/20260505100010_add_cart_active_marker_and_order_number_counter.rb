# Review fix C2 + I3:
# - C2: orders_carts に `active_marker` を導入し、(shop_id, customer_id, active_marker) を
#   UNIQUE にする。MySQL の UNIQUE は NULL を複数許容するので、active な cart は 1 つだけ
#   ・completed/abandoned cart は何個でも持てる、という不変条件を DB 制約で担保する。
# - I3: core_shops に `next_order_number` カラムを追加し、UPDATE で原子採番できるようにする。
#   `SELECT MAX FOR UPDATE` の MySQL 特殊挙動依存をやめ、別 DB でも安全に動くようにする。
class AddCartActiveMarkerAndOrderNumberCounter < ActiveRecord::Migration[8.1]
  def up
    # C2
    add_column :orders_carts, :active_marker, :integer
    Orders::Cart.reset_column_information
    Orders::Cart.where(status: Orders::Cart.statuses[:open]).update_all(active_marker: 1)
    add_index :orders_carts, [ :shop_id, :customer_id, :active_marker ],
              unique: true, name: "idx_orders_carts_one_active_per_customer"

    # I3
    add_column :core_shops, :next_order_number, :bigint, null: false, default: 1
  end

  def down
    remove_index :orders_carts, name: "idx_orders_carts_one_active_per_customer"
    remove_column :orders_carts, :active_marker
    remove_column :core_shops, :next_order_number
  end
end
