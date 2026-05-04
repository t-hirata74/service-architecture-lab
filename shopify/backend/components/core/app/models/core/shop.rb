module Core
  # ADR 0002: テナントの根。サブドメインで一意に解決される。
  class Shop < ApplicationRecord
    self.table_name = "core_shops"

    has_many :users, class_name: "Core::User", foreign_key: :shop_id, dependent: :destroy

    # Review fix I3: shop ごとの Order#number 採番カウンタ。
    # `Orders::CheckoutService#allocate_order_number!` から原子的にインクリメントされる。

    validates :subdomain, presence: true,
                          uniqueness: { case_sensitive: false },
                          format: { with: /\A[a-z0-9](?:[a-z0-9\-]{0,61}[a-z0-9])?\z/ }
    validates :name, presence: true
  end
end
