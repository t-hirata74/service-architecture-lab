module Catalog
  class Product < ApplicationRecord
    include TenantOwned
    self.table_name = "catalog_products"

    enum :status, { draft: 0, active: 1, archived: 2 }

    has_many :variants, class_name: "Catalog::Variant", dependent: :destroy

    validates :slug, presence: true, uniqueness: { scope: :shop_id, case_sensitive: false },
                     format: { with: /\A[a-z0-9](?:[a-z0-9\-]{0,61}[a-z0-9])?\z/ }
    validates :title, presence: true
  end
end
