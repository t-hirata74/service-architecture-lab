# Phase 5 / ADR 0004: 3rd-party App。secret は HMAC 鍵 (per-App 単一鍵 / rotation なしを ADR で明示)。
class CreateAppsApps < ActiveRecord::Migration[8.1]
  def change
    create_table :apps_apps do |t|
      t.string :name, null: false
      t.string :secret, null: false
      t.timestamps
    end
    add_index :apps_apps, :name, unique: true
  end
end
