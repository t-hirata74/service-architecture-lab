# Phase 2: Shop = テナント (ADR 0002)。サブドメインで解決する。
class CreateCoreShops < ActiveRecord::Migration[8.1]
  def change
    create_table :core_shops do |t|
      t.string :subdomain, null: false
      t.string :name, null: false
      t.timestamps
    end
    add_index :core_shops, :subdomain, unique: true
  end
end
