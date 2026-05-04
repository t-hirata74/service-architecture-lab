module Inventory
  class Location < ApplicationRecord
    include TenantOwned
    self.table_name = "inventory_locations"

    KINDS = %w[warehouse store dropship].freeze

    has_many :levels, class_name: "Inventory::InventoryLevel", dependent: :destroy

    validates :name, presence: true, uniqueness: { scope: :shop_id, case_sensitive: false }
    validates :kind, inclusion: { in: KINDS }
  end
end
