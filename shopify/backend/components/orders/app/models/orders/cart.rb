module Orders
  class Cart < ApplicationRecord
    include TenantOwned
    self.table_name = "orders_carts"

    enum :status, { open: 0, completed: 1, abandoned: 2 }

    belongs_to :customer, class_name: "Core::User"
    has_many :items, class_name: "Orders::CartItem", dependent: :destroy

    validate :customer_belongs_to_same_shop

    private

    def customer_belongs_to_same_shop
      return unless customer && shop_id && customer.shop_id != shop_id

      errors.add(:customer, "must belong to the same shop")
    end
  end
end
