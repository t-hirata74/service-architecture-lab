module Inventory
  # ADR 0003: 在庫数の truth。`Inventory::DeductService` 以外は更新しない。
  # `(variant_id, location_id)` で一意。
  class InventoryLevel < ApplicationRecord
    include TenantOwned
    self.table_name = "inventory_levels"

    belongs_to :variant, class_name: "Catalog::Variant"
    belongs_to :location, class_name: "Inventory::Location"

    validates :on_hand, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validates :variant_id, uniqueness: { scope: :location_id }
  end
end
