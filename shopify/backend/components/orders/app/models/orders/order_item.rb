module Orders
  class OrderItem < ApplicationRecord
    include TenantOwned
    self.table_name = "orders_order_items"

    belongs_to :order, class_name: "Orders::Order"
    belongs_to :variant, class_name: "Catalog::Variant"

    validates :quantity, numericality: { only_integer: true, greater_than: 0 }
    validates :unit_price_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validates :currency, presence: true, length: { is: 3 }
  end
end
