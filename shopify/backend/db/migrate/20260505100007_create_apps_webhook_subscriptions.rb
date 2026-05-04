class CreateAppsWebhookSubscriptions < ActiveRecord::Migration[8.1]
  def change
    create_table :apps_webhook_subscriptions do |t|
      t.references :shop, null: false, foreign_key: { to_table: :core_shops }
      t.references :app_installation, null: false, foreign_key: { to_table: :apps_app_installations }
      t.string :topic, null: false
      t.string :endpoint, null: false
      t.timestamps
    end
    add_index :apps_webhook_subscriptions, [ :shop_id, :topic ]
  end
end
