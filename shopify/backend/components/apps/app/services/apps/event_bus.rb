module Apps
  # ADR 0004: ドメインイベントの publish 入口。
  # 各 Engine の Service Object はこれを呼ぶだけで、subscriber 配信の詳細を知らなくてよい。
  #
  # publish は **呼び出し側のトランザクションに乗る**:
  #   - WebhookDelivery の INSERT
  #   - DeliveryJob の enqueue
  # この 2 つを同一 tx で行うことで、ドメインイベント発生 ⇔ 配信予約を原子的に紐付ける。
  module EventBus
    SUPPORTED_TOPICS = WebhookSubscription::SUPPORTED_TOPICS

    module_function

    def publish(topic:, payload:, shop:)
      raise ArgumentError, "unsupported topic: #{topic}" unless SUPPORTED_TOPICS.include?(topic.to_s)

      json = payload.to_json
      created = []

      WebhookSubscription.where(shop_id: shop.id, topic: topic.to_s).find_each do |sub|
        delivery = WebhookDelivery.create!(
          shop_id: shop.id,
          subscription_id: sub.id,
          delivery_id: SecureRandom.uuid,
          topic: topic.to_s,
          payload: json,
          status: :pending,
          attempts: 0
        )
        DeliveryJob.perform_later(delivery.id)
        created << delivery
      end

      created
    end
  end
end
