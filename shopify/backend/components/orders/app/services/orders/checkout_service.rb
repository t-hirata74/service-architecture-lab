module Orders
  class CheckoutError < StandardError; end
  class EmptyCartError < CheckoutError; end
  class CurrencyMismatchError < CheckoutError; end

  # Phase 4: Cart → Order 変換 + Inventory::DeductService を **同一トランザクション内**で呼び出す。
  # ADR 0003 に基づき、いずれか 1 つの SKU が在庫不足なら全体を rollback する。
  # ADR 0001 + ADR 0004: 完了後に ActiveSupport::Notifications.instrument("orders.order_created")
  # で publish。apps Engine が subscribe して webhook 配信を予約する (依存方向 fixate)。
  #
  # Review fixes:
  #   C1: cart に SELECT FOR UPDATE をかけ double-submit を防止
  #   C3: cart 内の variant currency 不整合を弾く
  #   I2: Inventory::DeductService に source: order を渡し ledger に紐付ける
  #   I3: Order#number は core_shops.next_order_number の原子インクリメントで採番
  class CheckoutService
    def self.call(cart:, location:)
      new(cart: cart, location: location).call
    end

    def initialize(cart:, location:)
      raise CheckoutError, "cart and location must belong to the same shop" if cart.shop_id != location.shop_id

      @cart = cart
      @location = location
    end

    def call
      Order.transaction do
        # C1: SELECT ... FOR UPDATE。同一 cart に対する並行 checkout を直列化する。
        # constructor で `cart.open?` をチェックするのではなく、lock 取得後に再評価することで
        # TOCTOU (time-of-check vs time-of-use) を防ぐ。
        @cart.lock!
        raise CheckoutError, "cart is not open" unless @cart.open?

        cart_items = @cart.items.includes(:variant).to_a
        raise EmptyCartError, "cart has no items" if cart_items.empty?

        validate_currency!(cart_items)

        order = build_order(cart_items)
        order.save!
        build_order_items!(order, cart_items)

        deduct_inventory!(cart_items, order)

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

    # Review fix C3: cart に複数 currency が混じった状態を弾く。
    # 通貨単位の異なる variant を素朴に price_cents 合算するとサイレントに不正な total が生まれる。
    def validate_currency!(cart_items)
      currencies = cart_items.map { |ci| ci.variant.currency }.uniq
      return if currencies.size == 1

      raise CurrencyMismatchError, "cart contains multiple currencies: #{currencies.inspect}"
    end

    def build_order(cart_items)
      currency = cart_items.first.variant.currency
      total = cart_items.sum { |ci| ci.variant.price_cents * ci.quantity }

      Order.new(
        shop_id: @cart.shop_id,
        customer_id: @cart.customer_id,
        number: allocate_order_number!,
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

    # Review fix I2: source: order を渡し、ledger から「どの Order で減算したか」を辿れるようにする。
    def deduct_inventory!(cart_items, order)
      cart_items.each do |ci|
        Inventory::DeductService.call(
          shop: @cart.shop,
          variant: ci.variant,
          location: @location,
          quantity: ci.quantity,
          reason: "order_deduct",
          source: order
        )
      end
    end

    # Review fix I3: shop ごとの原子採番。
    # `UPDATE core_shops SET next_order_number = next_order_number + 1 WHERE id = ?` を発行し、
    # その前の値を採番値として返す。MySQL の `SELECT MAX FOR UPDATE` 特殊挙動への依存をやめ、
    # 別 DB でも安全に動くシンプルな counter pattern。
    def allocate_order_number!
      shop = Core::Shop.where(id: @cart.shop_id).lock.first!
      number = shop.next_order_number
      shop.update!(next_order_number: number + 1)
      number
    end
  end
end
