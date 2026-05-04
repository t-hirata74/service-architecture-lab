module Core
  # rodauth の `accounts` テーブル。Core::User と共有 PK で 1:1。
  # 認証は core Engine の責務 (ADR 0001)。rodauth-rails 設定 (RodauthMain) 側でも
  # `Core::Account` を参照する。
  class Account < ApplicationRecord
    self.table_name = "accounts"

    has_one :user, class_name: "Core::User", foreign_key: :id, primary_key: :id, dependent: :destroy

    enum :status, { unverified: 1, verified: 2, closed: 3 }
  end
end
