# Phase 3: 暫定 User (Phase 4 で rodauth-rails の cookie auth に差し替え予定)。
# 当面は X-User-Id ヘッダで参照する.
class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :email, null: false, limit: 320
      t.timestamps
    end
    add_index :users, :email, unique: true
  end
end
