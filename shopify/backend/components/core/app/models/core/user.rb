module Core
  # ADR 0007 (perplexity と同形): rodauth の `accounts` と共有 PK で 1:1 紐付く。
  # ADR 0002: 必ず単一の Shop に所属する。
  class User < ApplicationRecord
    include TenantOwned
    self.table_name = "core_users"

    belongs_to :account, class_name: "::Account", foreign_key: :id, primary_key: :id, optional: true

    validates :email, presence: true, uniqueness: { scope: :shop_id, case_sensitive: false }
  end
end
