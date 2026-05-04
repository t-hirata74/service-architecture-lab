module Inventory
  class InsufficientStock < StandardError
    attr_reader :variant_id, :location_id, :requested
    def initialize(variant_id:, location_id:, requested:)
      @variant_id = variant_id
      @location_id = location_id
      @requested = requested
      super("insufficient stock: variant=#{variant_id} location=#{location_id} requested=#{requested}")
    end
  end

  # ADR 0003: 在庫減算の唯一の経路。
  # `UPDATE inventory_levels SET on_hand = on_hand - :q WHERE on_hand >= :q`
  # を発行し、affected_rows == 1 を確認。同一トランザクション内で ledger に追記する。
  #
  # 呼び出し側 (Phase 4 の Orders::CheckoutService) は **同一トランザクションの中で**
  # この service を呼ぶ。例外は呼び出し側の transaction を rollback させる。
  class DeductService
    def self.call(shop:, variant:, location:, quantity:, reason: "order_deduct", source: nil)
      new(shop: shop, variant: variant, location: location, quantity: quantity,
          reason: reason, source: source).call
    end

    def initialize(shop:, variant:, location:, quantity:, reason:, source:)
      raise ArgumentError, "quantity must be positive integer" unless quantity.is_a?(Integer) && quantity.positive?
      raise ArgumentError, "shop / variant / location must belong to the same tenant" unless tenant_consistent?(shop, variant, location)

      @shop = shop
      @variant = variant
      @location = location
      @quantity = quantity
      @reason = reason
      @source = source
    end

    def call
      InventoryLevel.transaction do
        affected = InventoryLevel
          .where(variant_id: @variant.id, location_id: @location.id)
          .where("on_hand >= ?", @quantity)
          .update_all([ "on_hand = on_hand - ?", @quantity ])

        if affected.zero?
          raise InsufficientStock.new(variant_id: @variant.id, location_id: @location.id, requested: @quantity)
        end

        StockMovement.create!(
          shop_id: @shop.id,
          variant_id: @variant.id,
          location_id: @location.id,
          delta: -@quantity,
          reason: @reason,
          source_type: @source&.class&.name,
          source_id: @source&.id
        )
      end
    end

    private

    def tenant_consistent?(shop, variant, location)
      shop.id == variant.shop_id && shop.id == location.shop_id
    end
  end
end
