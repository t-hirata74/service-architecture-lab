class CreateUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :users, id: false do |t|
      t.bigint :id, primary_key: true
      t.foreign_key :accounts, column: :id, on_delete: :cascade
      t.string :display_name, null: false
      t.timestamps precision: 6
    end
  end
end
