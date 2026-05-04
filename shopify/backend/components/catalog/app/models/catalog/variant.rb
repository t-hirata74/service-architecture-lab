module Catalog
  class Variant < ApplicationRecord
    include TenantOwned
    self.table_name = "catalog_variants"

    belongs_to :product, class_name: "Catalog::Product"

    validates :sku, presence: true, uniqueness: { scope: :shop_id, case_sensitive: false }
    validates :price_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validates :currency, presence: true, length: { is: 3 }

    validate :product_belongs_to_same_shop

    private

    def product_belongs_to_same_shop
      return unless product && shop_id && product.shop_id != shop_id

      errors.add(:product, "must belong to the same shop")
    end
  end
end
