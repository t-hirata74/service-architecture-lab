class CreateOrganizations < ActiveRecord::Migration[8.0]
  def change
    create_table :organizations do |t|
      t.string :login, null: false
      t.string :name, null: false, default: ""

      t.timestamps
    end

    add_index :organizations, :login, unique: true
  end
end
