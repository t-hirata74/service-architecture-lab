class CreateUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :users do |t|
      t.string :login, null: false
      t.string :name, null: false, default: ""
      t.string :email, null: false

      t.timestamps
    end

    add_index :users, :login, unique: true
    add_index :users, :email, unique: true
  end
end
