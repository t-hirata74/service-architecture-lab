module Orders
  module Storefront
    # 認証済み buyer の現在の open cart を取り回す。
    class CartsController < ::ApplicationController
      before_action :authenticate_user!

      # GET /storefront/cart
      def show
        cart = current_open_cart
        render json: serialize_cart(cart)
      end

      # POST /storefront/cart/items  body: { variant_id, quantity }
      def add_item
        cart = current_open_cart
        variant = Catalog::Variant.where(shop_id: current_shop.id, id: params[:variant_id]).first!

        item = cart.items.find_or_initialize_by(variant_id: variant.id) do |i|
          i.shop_id = current_shop.id
          i.quantity = 0
        end
        item.quantity += params[:quantity].to_i.clamp(1, 99)
        item.save!

        render json: serialize_cart(cart.reload), status: :created
      end

      # DELETE /storefront/cart/items/:variant_id
      def remove_item
        cart = current_open_cart
        cart.items.where(variant_id: params[:variant_id]).destroy_all
        render json: serialize_cart(cart.reload)
      end

      private

      def current_open_cart
        Orders::Cart.find_or_create_by!(shop_id: current_shop.id, customer_id: current_user.id, status: Orders::Cart.statuses[:open])
      end

      def serialize_cart(cart)
        {
          id: cart.id,
          status: cart.status,
          items: cart.items.includes(:variant).map { |i|
            {
              variant_id: i.variant_id,
              sku: i.variant.sku,
              quantity: i.quantity,
              price_cents: i.variant.price_cents,
              currency: i.variant.currency
            }
          }
        }
      end
    end
  end
end
