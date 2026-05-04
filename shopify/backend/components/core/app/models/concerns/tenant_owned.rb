# ADR 0002: tenant-scoped な model はこの concern を必ず include する。
# `belongs_to :shop` を強制し、`shop_id` 抜きで保存できないようにする。
# 「全 tenant-scoped model がこれを include しているか」は spec で fixate する。
module TenantOwned
  extend ActiveSupport::Concern

  included do
    belongs_to :shop, class_name: "Core::Shop"
    validates :shop_id, presence: true
  end
end
