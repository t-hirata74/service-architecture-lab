module Orders
  module Storefront
    # POST /storefront/checkout — open cart を Order に変換 (CheckoutService 経由)。
    # 在庫不足は 409 Conflict、それ以外の business error は 422。
    class CheckoutsController < ::ApplicationController
      before_action :authenticate_user!

      def create
        cart = Orders::Cart.where(shop_id: current_shop.id, customer_id: current_user.id, status: Orders::Cart.statuses[:open]).first!
        location = default_location!

        order = Orders::CheckoutService.call(cart: cart, location: location)

        render json: serialize_order(order), status: :created
      rescue Inventory::InsufficientStock => e
        render json: { error: "insufficient_stock", variant_id: e.variant_id, requested: e.requested }, status: :conflict
      rescue Orders::EmptyCartError
        render json: { error: "empty_cart" }, status: :unprocessable_entity
      rescue Orders::CheckoutError => e
        render json: { error: e.message }, status: :unprocessable_entity
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
