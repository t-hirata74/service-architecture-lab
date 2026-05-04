class CreateAppsAppInstallations < ActiveRecord::Migration[8.1]
  def change
    create_table :apps_app_installations do |t|
      t.references :shop, null: false, foreign_key: { to_table: :core_shops }
      t.references :app, null: false, foreign_key: { to_table: :apps_apps }
      t.string :api_token_digest, null: false
      t.string :scopes, null: false, default: ""
      t.timestamps
    end
    add_index :apps_app_installations, [ :shop_id, :app_id ], unique: true
    add_index :apps_app_installations, :api_token_digest, unique: true
  end
end
