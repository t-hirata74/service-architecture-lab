module Apps
  # Shop ごとに「どの topic を、どの endpoint に投げるか」を表現する。
  class WebhookSubscription < ApplicationRecord
    include TenantOwned
    self.table_name = "apps_webhook_subscriptions"

    SUPPORTED_TOPICS = %w[order_created inventory_updated].freeze

    belongs_to :app_installation, class_name: "Apps::AppInstallation"
    has_many :deliveries, class_name: "Apps::WebhookDelivery", foreign_key: :subscription_id, dependent: :destroy

    validates :topic, presence: true, inclusion: { in: SUPPORTED_TOPICS }
    validates :endpoint, presence: true, format: { with: %r{\Ahttps?://} }
  end
end
