module Apps
  module Api
    # ADR 0004: 3rd-party App が installation の shop の Order を読む API。
    # `read_orders` scope を要求する。
    class OrdersController < BaseController
      def index
        requires_scope!("read_orders")

        orders = ::Orders::Order.where(shop_id: current_shop.id).order(number: :desc).limit(50)
        render json: orders.map { |o| serialize_order(o) }
      end

      private

      def serialize_order(order)
        {
          id: order.id,
          number: order.number,
          status: order.status,
          total_cents: order.total_cents,
          currency: order.currency,
          created_at: order.created_at.iso8601
        }
      end
    end
  end
end
