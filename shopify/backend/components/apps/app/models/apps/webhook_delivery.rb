module Apps
  # at-least-once 配信状態。pending → delivered (2xx) / failed_permanent (max_attempts 到達)。
  # 5xx / network error は attempts++ + next_attempt_at = backoff(attempts) で retry 待機状態に戻る。
  class WebhookDelivery < ApplicationRecord
    include TenantOwned
    self.table_name = "apps_webhook_deliveries"

    MAX_ATTEMPTS = 8

    enum :status, { pending: 0, delivered: 1, failed_permanent: 2 }

    belongs_to :subscription, class_name: "Apps::WebhookSubscription"

    validates :delivery_id, presence: true, uniqueness: true
    validates :topic, presence: true
    validates :payload, presence: true

    def parsed_payload
      JSON.parse(payload)
    end

    # exponential backoff: 2^attempts seconds + 30s jitter (テスト容易性のため定数で)
    def self.backoff_seconds(attempts)
      (2**attempts).clamp(1, 3600)
    end
  end
end
