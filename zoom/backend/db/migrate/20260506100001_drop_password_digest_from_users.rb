# Phase 4-3: 認証は rodauth-rails (accounts.password_hash) に寄せるため、
# users.password_digest は不要。User テーブルからは email + display_name のみ残す。
# accounts と users は shared PK で 1:1 (shopify と同形)。
class DropPasswordDigestFromUsers < ActiveRecord::Migration[8.1]
  def change
    remove_column :users, :password_digest, :string, null: false
  end
end
