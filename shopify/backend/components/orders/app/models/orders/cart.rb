module Orders
  class Cart < ApplicationRecord
    include TenantOwned
    self.table_name = "orders_carts"

    enum :status, { open: 0, completed: 1, abandoned: 2 }

    belongs_to :customer, class_name: "Core::User"
    has_many :items, class_name: "Orders::CartItem", dependent: :destroy

    # Review fix C2: open な cart は customer ごとに 1 つだけ。
    # `active_marker` は status=open の時 1、それ以外は NULL。
    # `(shop_id, customer_id, active_marker)` UNIQUE は MySQL の NULL 複数許容性により、
    # 「active な cart は 1 つ」かつ「completed/abandoned は何個でも持てる」を担保する。
    before_validation :sync_active_marker

    validate :customer_belongs_to_same_shop

    private

    def sync_active_marker
      self.active_marker = open? ? 1 : nil
    end

    def customer_belongs_to_same_shop
      return unless customer && shop_id && customer.shop_id != shop_id

      errors.add(:customer, "must belong to the same shop")
    end
  end
end
