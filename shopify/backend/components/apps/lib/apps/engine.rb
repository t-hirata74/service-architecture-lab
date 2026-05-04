module Apps
  class Engine < ::Rails::Engine
    isolate_namespace Apps

    # ADR 0001 + ADR 0004: orders Engine が `orders.order_created` を ActiveSupport::Notifications で
    # publish する。apps はそれを subscribe して webhook 配信のキックを担当する。
    # 依存方向 (apps → orders) はこの形で守られる: orders は apps を直接参照しない。
    config.after_initialize do
      ActiveSupport::Notifications.subscribe("orders.order_created") do |*, payload|
        shop = payload[:shop]
        body = payload[:payload]
        Apps::EventBus.publish(topic: :order_created, payload: body, shop: shop) if shop
      end
    end
  end
end
