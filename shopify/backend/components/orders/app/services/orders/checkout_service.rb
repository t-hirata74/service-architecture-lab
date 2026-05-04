module Orders
  class CheckoutError < StandardError; end
  class EmptyCartError < CheckoutError; end

  # Phase 4: Cart → Order 変換 + Inventory::DeductService を **同一トランザクション内**で呼び出す。
  # ADR 0003 に基づき、いずれか 1 つの SKU が在庫不足なら全体を rollback する。
  # ADR 0004 (Phase 5): 完了後に Apps::EventBus.publish(:order_created, ...) を呼ぶ予定。
  class CheckoutService
    def self.call(cart:, location:)
      new(cart: cart, location: location).call
    end

    def initialize(cart:, location:)
      raise CheckoutError, "cart is not open" unless cart.open?
      raise CheckoutError, "cart and location must belong to the same shop" if cart.shop_id != location.shop_id

      @cart = cart
      @location = location
    end

    def call
      Order.transaction do
        cart_items = @cart.items.includes(:variant).to_a
        raise EmptyCartError, "cart has no items" if cart_items.empty?

        order = build_order(cart_items)
        order.save!
        build_order_items!(order, cart_items)

        deduct_inventory!(cart_items)

        @cart.update!(status: :completed)

        publish_order_created(order, cart_items)

        order
      end
    end

    # ADR 0001 (依存方向 apps → orders): orders は apps を直接参照できない。
    # ActiveSupport::Notifications で dependency inversion を行い、
    # apps Engine は initializer で `orders.order_created` を subscribe する。
    def publish_order_created(order, cart_items)
      ActiveSupport::Notifications.instrument(
        "orders.order_created",
        shop: @cart.shop,
        payload: {
          order_id: order.id,
          number: order.number,
          total_cents: order.total_cents,
          currency: order.currency,
          items: cart_items.map { |ci| { variant_id: ci.variant_id, quantity: ci.quantity } }
        }
      )
    end

    private

    def build_order(cart_items)
      currency = cart_items.first.variant.currency
      total = cart_items.sum { |ci| ci.variant.price_cents * ci.quantity }

      Order.new(
        shop_id: @cart.shop_id,
        customer_id: @cart.customer_id,
        number: next_order_number,
        status: :paid,
        total_cents: total,
        currency: currency
      )
    end

    def build_order_items!(order, cart_items)
      cart_items.each do |ci|
        OrderItem.create!(
          shop_id: @cart.shop_id,
          order_id: order.id,
          variant_id: ci.variant_id,
          quantity: ci.quantity,
          unit_price_cents: ci.variant.price_cents,
          currency: ci.variant.currency
        )
      end
    end

    def deduct_inventory!(cart_items)
      cart_items.each do |ci|
        Inventory::DeductService.call(
          shop: @cart.shop,
          variant: ci.variant,
          location: @location,
          quantity: ci.quantity,
          reason: "order_deduct"
        )
      end
    end

    # shop 単位のシーケンシャル採番。MAX(number) FOR UPDATE で隣接 transaction の同時採番を防ぐ。
    def next_order_number
      current = Order.where(shop_id: @cart.shop_id).lock("FOR UPDATE").maximum(:number) || 0
      current + 1
    end
  end
end
