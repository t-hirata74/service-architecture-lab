# Phase 5 / ADR 0004: at-least-once 配信のための DB-backed delivery 状態。
# delivery_id は UUID、X-Webhook-Delivery-Id として受信側に渡す (冪等性 key)。
class CreateAppsWebhookDeliveries < ActiveRecord::Migration[8.1]
  def change
    create_table :apps_webhook_deliveries do |t|
      t.references :shop, null: false, foreign_key: { to_table: :core_shops }
      t.references :subscription, null: false, foreign_key: { to_table: :apps_webhook_subscriptions }
      t.string :delivery_id, null: false
      t.string :topic, null: false
      t.text :payload, null: false
      t.integer :status, null: false, default: 0
      t.integer :attempts, null: false, default: 0
      t.datetime :next_attempt_at
      t.datetime :delivered_at
      t.text :last_error
      t.timestamps
    end
    add_index :apps_webhook_deliveries, :delivery_id, unique: true
    add_index :apps_webhook_deliveries, [ :status, :next_attempt_at ]
  end
end
