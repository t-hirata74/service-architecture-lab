module Orders
  module Storefront
    # POST /storefront/checkout — open cart を Order に変換 (CheckoutService 経由)。
    # 在庫不足は 409 Conflict、それ以外の business error は 422。
    #
    # Review fix M3 (C1 余波): ActiveRecord::Deadlocked は再試行可能な一時エラーなので
    # 409 Conflict で `retryable: true` を返す。
    class CheckoutsController < ::ApplicationController
      before_action :authenticate_user!

      def create
        cart = Orders::Cart.where(shop_id: current_shop.id, customer_id: current_user.id, status: Orders::Cart.statuses[:open]).first!
        location = default_location!

        order = Orders::CheckoutService.call(cart: cart, location: location)

        render json: serialize_order(order), status: :created
      rescue Inventory::InsufficientStock => e
        render json: { error: "insufficient_stock", variant_id: e.variant_id, requested: e.requested }, status: :conflict
      rescue Inventory::NotConfigured => e
        render json: { error: "inventory_not_configured", variant_id: e.variant_id, location_id: e.location_id }, status: :unprocessable_entity
      rescue Orders::CurrencyMismatchError => e
        render json: { error: "currency_mismatch", message: e.message }, status: :unprocessable_entity
      rescue Orders::EmptyCartError
        render json: { error: "empty_cart" }, status: :unprocessable_entity
      rescue Orders::CheckoutError => e
        render json: { error: e.message }, status: :unprocessable_entity
      rescue ActiveRecord::Deadlocked
        # MySQL が並行 transaction の victim を選んだケース。リトライすれば成功する可能性が高い。
        render json: { error: "concurrent_checkout_conflict", retryable: true }, status: :conflict
      end

      private

      def default_location!
        Inventory::Location.where(shop_id: current_shop.id).order(:id).first ||
          (raise Orders::CheckoutError, "no inventory location configured for shop")
      end

      def serialize_order(order)
        {
          id: order.id,
          number: order.number,
          status: order.status,
          total_cents: order.total_cents,
          currency: order.currency,
          items: order.items.map { |i| { variant_id: i.variant_id, quantity: i.quantity, unit_price_cents: i.unit_price_cents } }
        }
      end
    end
  end
end
