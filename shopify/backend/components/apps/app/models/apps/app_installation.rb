module Apps
  # App ↔ Shop の M:N 結節。api_token は SHA256 hash で永続化、生 token は install 時のみ返す。
  class AppInstallation < ApplicationRecord
    include TenantOwned
    self.table_name = "apps_app_installations"

    belongs_to :app, class_name: "Apps::App"
    has_many :webhook_subscriptions, class_name: "Apps::WebhookSubscription", dependent: :destroy

    validates :api_token_digest, presence: true, uniqueness: true

    def self.digest_token(token)
      Digest::SHA256.hexdigest(token)
    end

    def scope_list
      scopes.to_s.split(",").map(&:strip).reject(&:empty?)
    end

    def has_scope?(name)
      scope_list.include?(name.to_s)
    end
  end
end
