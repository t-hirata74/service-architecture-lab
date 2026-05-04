module Orders
  class Order < ApplicationRecord
    include TenantOwned
    self.table_name = "orders_orders"

    enum :status, { paid: 0, fulfilled: 1, refunded: 2, cancelled: 3 }

    belongs_to :customer, class_name: "Core::User"
    has_many :items, class_name: "Orders::OrderItem", dependent: :destroy

    validates :number, presence: true, numericality: { only_integer: true, greater_than: 0 }
    validates :total_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validates :currency, presence: true, length: { is: 3 }
  end
end
