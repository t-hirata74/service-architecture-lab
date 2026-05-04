module Inventory
  # ADR 0003: append-only ledger。delete / update を model 経由で禁止する。
  # `SUM(delta) + initial == on_hand` の不変条件はこの table が責任を持つ。
  class StockMovement < ApplicationRecord
    include TenantOwned
    self.table_name = "inventory_stock_movements"

    REASONS = %w[seed order_deduct order_release adjustment reconcile].freeze

    belongs_to :variant, class_name: "Catalog::Variant"
    belongs_to :location, class_name: "Inventory::Location"

    validates :delta, numericality: { only_integer: true, other_than: 0 }
    validates :reason, inclusion: { in: REASONS }

    def readonly?
      persisted?
    end
  end
end
