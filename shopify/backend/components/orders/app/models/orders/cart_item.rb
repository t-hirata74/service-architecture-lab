module Orders
  class CartItem < ApplicationRecord
    include TenantOwned
    self.table_name = "orders_cart_items"

    belongs_to :cart, class_name: "Orders::Cart"
    belongs_to :variant, class_name: "Catalog::Variant"

    validates :quantity, numericality: { only_integer: true, greater_than: 0 }
    validates :variant_id, uniqueness: { scope: :cart_id }
  end
end
