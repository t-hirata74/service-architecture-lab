# Phase 3: 1 ユーザクエリ = 1 行. status: pending / streaming / completed / failed
class CreateQueries < ActiveRecord::Migration[8.1]
  def change
    create_table :queries do |t|
      t.references :user, null: false, foreign_key: true
      t.text :text, null: false
      t.string :status, null: false, default: "pending", limit: 16
      t.timestamps
    end
    add_index :queries, %i[user_id created_at]
  end
end
